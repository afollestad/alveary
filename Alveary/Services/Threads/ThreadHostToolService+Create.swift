import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// Creates a thread immediately. There is no confirmation step: a created thread is visible,
    /// inert until its prompt runs, and the user can archive it — so a confirmation pane would
    /// cost more than the mistake it prevents.
    func createThread(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let requestID = try requireRequestID(context)
        try flushPendingChanges()
        let requestDate = requestDate()
        let source = try resolveSource(context: context)
        let parsed = try parseCreate(arguments: arguments)
        let deduplicationKey = HostToolDeduplication.key(
            sourceConversationID: context.conversationId.rawValue,
            processToken: context.processToken,
            requestID: requestID,
            canonicalPayloadHash: parsed.canonicalPayloadHash
        )

        // An exact retry replays its receipt: it creates nothing, and it does not re-dispatch the
        // initial prompt, which is the part that would otherwise be visibly duplicated.
        if let receipt = try replayedReceipt(
            on: source.conversation,
            deduplicationKey: deduplicationKey,
            processToken: context.processToken,
            at: requestDate
        ) {
            return replayedCreateResult(receipt: receipt)
        }

        // Snapshot before the resolver's suspension; SwiftData models must not be read across it.
        let placement = ThreadHostToolSourcePlacement(thread: source.thread)
        let defaults = try await resolvedSettingDefaults(
            source: source,
            fallbackProvider: context.providerId.rawValue,
            requestedProvider: parsed.provider
        )
        let request = try validatedCreateRequest(parsed, placement: placement, defaults: defaults)
        let insertion = try insert(request, sourceConversationID: context.conversationId.rawValue)

        // The receipt saves separately from the thread: a failed ledger write must not roll back a
        // thread the user can already see.
        try persistReceipt(
            ThreadHostToolReceipt(
                deduplicationKey: deduplicationKey,
                threadID: insertion.created.threadID,
                name: insertion.created.name,
                status: "created",
                message: insertion.created.message,
                sourceProcessToken: context.processToken.uuidString.lowercased(),
                createdAt: requestDate
            ),
            on: insertion.sourceConversation
        )

        if let initialPrompt = request.initialPrompt {
            // Fire-and-forget: the tool claims dispatch, never an outcome, so a spawn failure
            // surfaces as a retryable first message on the new thread rather than a tool error.
            startInitialPrompt(insertion.conversation, initialPrompt)
        }
        return insertion.created.result
    }
}

private extension ThreadHostToolService {
    /// Re-resolves every model after the defaults resolver's suspension — the Project or the
    /// calling conversation could have been removed while it awaited — then inserts.
    func insert(
        _ request: ThreadHostToolCreateRequest,
        sourceConversationID: String
    ) throws -> ThreadHostToolInsertion {
        guard let sourceConversation = modelContext.resolveConversation(conversationID: sourceConversationID) else {
            throw ThreadHostToolServiceError.sourceConversationUnavailable
        }
        let thread = try insertThread(request)
        guard let conversation = thread.soleMainConversation else {
            throw ThreadHostToolServiceError.persistenceFailure
        }
        return ThreadHostToolInsertion(
            conversation: conversation,
            sourceConversation: sourceConversation,
            created: ThreadHostToolCreatedThread(
                threadID: conversation.id,
                name: thread.displayName(),
                workspace: request.workspace,
                provider: request.provider,
                model: request.model,
                effort: request.effort,
                permissionMode: request.permissionMode,
                isPinned: thread.isPinned,
                sectionName: createdSectionName(for: thread),
                dispatchedInitialPrompt: request.initialPrompt != nil
            )
        )
    }

    /// Read from the inserted row rather than the request, so the reported section is the
    /// membership the thread actually got — a Project thread reports none at all, and a thread
    /// created pinned reports the section it returns to on unpin.
    func createdSectionName(for thread: AgentThread) -> String? {
        guard thread.project == nil, thread.effectiveMode == .task else {
            return nil
        }
        return thread.customSection?.name ?? SidebarSectionKind.tasks.builtinDisplayName
    }

    func insertThread(_ request: ThreadHostToolCreateRequest) throws -> AgentThread {
        switch request.workspace {
        case .project(let path):
            guard let project = modelContext.resolveProject(path: path) else {
                throw ThreadHostToolServiceError.projectNotRegistered(path: path)
            }
            return try lifecycleService.insertProjectThread(
                project: project,
                seed: ProjectThreadSeed(
                    provider: request.provider,
                    permissionMode: request.permissionMode,
                    model: request.model,
                    effort: request.effort,
                    isDraft: false,
                    name: request.name,
                    pinned: request.pinned
                )
            )
        case .task(let grantedRoots, let placement):
            return try lifecycleService.insertTaskThread(
                seed: TaskThreadSeed(
                    provider: request.provider,
                    permissionMode: request.permissionMode,
                    model: request.model,
                    effort: request.effort,
                    isDraft: false,
                    name: request.name,
                    pinned: request.pinned,
                    grantedRoots: grantedRoots,
                    // Re-resolved from plain values inside the creating save; only strings
                    // crossed the defaults resolver's `await`, never a SwiftData row.
                    placement: placement
                )
            )
        }
    }

    func replayedCreateResult(receipt: ThreadHostToolReceipt) -> AgentCLIKit.AgentHostToolResult {
        var structuredContent: [String: AgentCLIKit.JSONValue] = [
            "status": .string("created"),
            "thread_id": .string(receipt.threadID),
            "message": .string(receipt.message)
        ]
        if let name = receipt.name {
            structuredContent["name"] = .string(name)
        }
        return AgentCLIKit.AgentHostToolResult(
            text: receipt.message,
            structuredContent: .object(structuredContent)
        )
    }

    /// Assembles the validated request; `ThreadHostToolService+CreateSettings.swift` owns how each
    /// setting inherits, falls back, and validates.
    func validatedCreateRequest(
        _ parsed: ThreadHostToolParsedCreateRequest,
        placement: ThreadHostToolSourcePlacement,
        defaults: ThreadSettingDefaults
    ) throws -> ThreadHostToolCreateRequest {
        let model = try validatedModel(parsed.model, defaults: defaults)
        let effort = try validatedEffort(parsed.effort, defaults: defaults, model: model)
        let permissionMode = try validatedPermissionMode(
            parsed.permissionMode,
            provider: defaults.provider,
            resolution: defaults.resolution
        )
        return ThreadHostToolCreateRequest(
            workspace: try validatedWorkspace(parsed.workspace, placement: placement),
            name: parsed.name,
            provider: defaults.provider,
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            initialPrompt: parsed.initialPrompt,
            pinned: parsed.pinned ?? false
        )
    }

    /// Turns the requested placement into the one the thread is created with. The parser settled
    /// shape; where the caller works and whether a granted folder exists are host state, so both
    /// are resolved here.
    ///
    /// A request that named no placement lands wherever the calling thread already works, which is
    /// what "create a thread" usually means and is trusted state rather than a guess at a dropped
    /// `project_path`. Grants cannot ride an inherited Project placement, so they are refused
    /// rather than silently dropped. A task workspace additionally inherits the caller's sidebar
    /// placement when the request names no `section`.
    func validatedWorkspace(
        _ requested: ThreadHostToolRequestedWorkspace,
        placement: ThreadHostToolSourcePlacement
    ) throws -> ThreadHostToolCreateWorkspace {
        switch requested {
        case .project(let path):
            return .project(path: path)
        case .task(let grantedRoots, let sectionName):
            return try validatedTaskWorkspace(
                grantedRoots: grantedRoots,
                sectionName: sectionName,
                placement: placement
            )
        case .inherit(let grantedRoots):
            switch placement.mode {
            case .task:
                return try validatedTaskWorkspace(
                    grantedRoots: grantedRoots,
                    sectionName: nil,
                    placement: placement
                )
            case .project:
                guard grantedRoots.isEmpty else {
                    throw ThreadHostToolServiceError.grantsRequireTaskThread
                }
                guard let projectPath = placement.projectPath else {
                    throw ThreadHostToolServiceError.sourcePlacementUnavailable
                }
                return .project(path: projectPath)
            }
        }
    }

    /// Settles a task workspace's sidebar placement and grants together, because they are
    /// coupled: nesting under a project also grants that project's folder, mirroring the
    /// sidebar's Task-to-Project drop. An explicit `section` is the override that opts a spawn
    /// out of inheriting the caller's placement — `Tasks` for the plain list.
    func validatedTaskWorkspace(
        grantedRoots: [String],
        sectionName: String?,
        placement: ThreadHostToolSourcePlacement
    ) throws -> ThreadHostToolCreateWorkspace {
        let roots = try canonicalGrantedRoots(grantedRoots)
        if let sectionName {
            guard let sectionID = try resolvedSectionID(named: sectionName) else {
                return .task(grantedRoots: roots)
            }
            return .task(grantedRoots: roots, placement: .section(id: sectionID))
        }
        switch inheritedTaskPlacement(placement) {
        case .project(let path):
            // The nested project's folder joins the grants; one that fails canonicalization
            // drops the nesting instead, because an inherited default the request never named
            // must not fail the create.
            guard let projectRoot = try? canonicalGrantedRoots([path]).first else {
                return .task(grantedRoots: roots)
            }
            let merged = roots.contains(projectRoot) ? roots : roots + [projectRoot]
            return .task(grantedRoots: merged, placement: .project(path: path))
        case .section(let sectionID):
            return .task(grantedRoots: roots, placement: .section(id: sectionID))
        case .tasks:
            return .task(grantedRoots: roots)
        }
    }

    /// The sidebar placement an omitted `section` inherits: the caller's own project nesting or
    /// custom section, re-resolved against live rows because the snapshot predates the defaults
    /// resolver's `await`. A row that vanished across it falls back to the plain `Tasks` list
    /// rather than failing a create that never named it — unlike an explicitly named section or
    /// project, which stays strict.
    func inheritedTaskPlacement(_ placement: ThreadHostToolSourcePlacement) -> TaskThreadSidebarPlacement {
        if let projectPath = placement.projectPath {
            guard modelContext.resolveProject(path: projectPath) != nil else {
                return .tasks
            }
            return .project(path: projectPath)
        }
        if let sectionID = placement.sectionID {
            guard let section = modelContext.resolveSidebarSection(id: sectionID),
                  section.kind == .custom else {
                return .tasks
            }
            return .section(id: sectionID)
        }
        return .tasks
    }

    /// The section a `create_thread` request named, as a `SidebarSection.id`.
    ///
    /// `Tasks` resolves to nil — a Task with no membership already renders there — and every other
    /// built-in is refused, because a thread cannot live in `Pinned` or `Projects`. An unknown name
    /// is refused rather than created: composing `create_section` first keeps a typo from silently
    /// minting a section the user never asked for.
    func resolvedSectionID(named sectionName: String) throws -> String? {
        let match = try sectionMatch(named: sectionName)
        switch match.id {
        case .tasks:
            return nil
        case .custom(let sectionID):
            return sectionID
        case .pinned, .projects:
            throw ThreadHostToolServiceError.sectionNotCustom(name: match.name)
        }
    }

    /// Each grant must be an absolute path to an existing folder and is stored canonically
    /// resolved — the same rule `propose_scheduled_task`'s `granted_roots` follows — so a symlink
    /// spelling cannot show the user one folder while granting another. Two spellings of the same
    /// folder collapse, which the parser's literal duplicate check cannot see.
    func canonicalGrantedRoots(_ requested: [String]) throws -> [String] {
        var canonical: [String] = []
        for path in requested {
            guard path.hasPrefix("/") else {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
            }
            let normalized = CanonicalPath.normalize(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ThreadHostToolServiceError.grantedRootUnavailable(path: path)
            }
            if !canonical.contains(normalized) {
                canonical.append(normalized)
            }
        }
        return canonical
    }
}

/// The freshly inserted thread's live models, kept together so the caller does not re-fetch them.
private struct ThreadHostToolInsertion {
    let conversation: Conversation
    let sourceConversation: Conversation
    let created: ThreadHostToolCreatedThread
}

/// What `create_thread` produced, rendered into both result shapes from one place.
private struct ThreadHostToolCreatedThread {
    let threadID: String
    let name: String
    let workspace: ThreadHostToolCreateWorkspace
    let provider: String
    let model: String?
    let effort: String
    let permissionMode: String
    let isPinned: Bool
    /// The section the created thread renders in, resolved at insert time. Nil for a Project
    /// thread, which renders under its Project rather than in any section.
    let sectionName: String?
    let dispatchedInitialPrompt: Bool

    var message: String {
        var message = "Created the thread \"\(name)\" \(workspaceSummary) (id: \(threadID)) using \(provider), " +
            "model \(model ?? AppSettings.defaultModelValue), effort \(effort), permissions \(permissionMode)"
        message += isPinned ? ", pinned." : "."
        if case .task(let grantedRoots, _) = workspace, !grantedRoots.isEmpty {
            message += " It can also reach \(grantedRoots.joined(separator: ", "))."
        }
        if dispatchedInitialPrompt {
            message += " Its first prompt is running in the background; its results appear in that thread, not here."
        }
        return message
    }

    var result: AgentCLIKit.AgentHostToolResult {
        var content: [String: AgentCLIKit.JSONValue] = [
            "status": .string("created"),
            "thread_id": .string(threadID),
            "name": .string(name),
            "workspace_kind": .string(workspace.kind.rawValue),
            "provider": .string(provider),
            "model": .string(model ?? AppSettings.defaultModelValue),
            "effort": .string(effort),
            "permission_mode": .string(permissionMode),
            "is_pinned": .bool(isPinned),
            "initial_prompt_dispatched": .bool(dispatchedInitialPrompt),
            "message": .string(message)
        ]
        switch workspace {
        case .project(let path):
            content["project_path"] = .string(path)
        case .task(let grantedRoots, let placement):
            content["granted_roots"] = .array(grantedRoots.map(AgentCLIKit.JSONValue.string))
            if case .project(let path) = placement {
                content["project_path"] = .string(path)
            }
        }
        if let sectionName {
            content["section"] = .string(sectionName)
        }
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }

    private var workspaceSummary: String {
        switch workspace {
        case .project(let path):
            "in \(path)"
        case .task(_, .project(let path)):
            "in its own private workspace, shown under \(path)"
        case .task:
            "in its own private workspace"
        }
    }
}
