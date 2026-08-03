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
        let source = try resolveMutatingSource(context: context)
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
        let settings = settingsService.current
        let placement = ThreadHostToolSourcePlacement(thread: source.thread)
        let resolution = await resolvedThreadDefaults(settings: settings)
        let provider = try validatedProvider(parsed.provider, resolution: resolution)
        let providerOptions = await modelOptions(for: provider, resolution: resolution)
        let request = try validatedCreateRequest(
            parsed,
            placement: placement,
            provider: provider,
            options: providerOptions,
            resolution: resolution
        )
        let insertion = try insert(request, sourceConversationID: context.conversationId.rawValue)

        // The receipt saves separately from the thread: a failed ledger write must not roll back a
        // thread the user can already see.
        try persistReceipt(
            ThreadHostToolReceipt(
                deduplicationKey: deduplicationKey,
                threadID: insertion.created.threadID,
                name: insertion.created.name,
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
                dispatchedInitialPrompt: request.initialPrompt != nil
            )
        )
    }

    func insertThread(_ request: ThreadHostToolCreateRequest) throws -> AgentThread {
        switch request.workspace {
        case .project(let path):
            guard let project = resolveProject(path: path) else {
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
        case .task(let grantedRoots):
            return try lifecycleService.insertTaskThread(
                seed: TaskThreadSeed(
                    provider: request.provider,
                    permissionMode: request.permissionMode,
                    model: request.model,
                    effort: request.effort,
                    isDraft: false,
                    name: request.name,
                    pinned: request.pinned,
                    grantedRoots: grantedRoots
                )
            )
        }
    }

    func replayedReceipt(
        on sourceConversation: Conversation,
        deduplicationKey: String,
        processToken: UUID,
        at requestDate: Date
    ) throws -> ThreadHostToolReceipt? {
        do {
            let receipt = try sourceConversation.threadHostToolReceipt(
                matching: deduplicationKey,
                currentProcessToken: processToken,
                at: requestDate
            )
            if modelContext.hasChanges {
                try modelContext.save()
            }
            return receipt
        } catch {
            modelContext.rollback()
            throw ThreadHostToolServiceError.persistenceFailure
        }
    }

    func persistReceipt(
        _ receipt: ThreadHostToolReceipt,
        on sourceConversation: Conversation
    ) throws {
        do {
            try sourceConversation.recordThreadHostToolReceipt(receipt)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ThreadHostToolServiceError.persistenceFailure
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

    func resolvedThreadDefaults(settings: AppSettings) async -> ThreadDefaultResolution {
        if let providerDiscovery {
            return await ThreadDefaultResolver.resolve(
                settings: settings,
                providerDiscovery: providerDiscovery
            )
        }
        return ThreadDefaultResolver.resolve(
            settings: settings,
            providerOrdering: AppSettings.supportedProviderIDs,
            providerStatuses: [:],
            allowStaticFallback: true
        )
    }

    func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? modelContext.fetch(descriptor).first
    }

    /// Every setting is validated against what this Mac can actually run, and each rejection names
    /// the valid values so the model can correct itself instead of guessing again.
    func validatedCreateRequest(
        _ parsed: ThreadHostToolParsedCreateRequest,
        placement: ThreadHostToolSourcePlacement,
        provider: String,
        options providerOptions: [AgentCLIKit.AgentModelOption],
        resolution: ThreadDefaultResolution
    ) throws -> ThreadHostToolCreateRequest {
        let model = try validatedModel(parsed.model, options: providerOptions, resolution: resolution, provider: provider)
        let effort = try validatedEffort(parsed.effort, options: providerOptions, model: model, resolution: resolution, provider: provider)
        let permissionMode = try validatedPermissionMode(parsed.permissionMode, provider: provider, resolution: resolution)
        return ThreadHostToolCreateRequest(
            workspace: try validatedWorkspace(parsed.workspace, placement: placement),
            name: parsed.name,
            provider: provider,
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
    /// rather than silently dropped.
    func validatedWorkspace(
        _ requested: ThreadHostToolRequestedWorkspace,
        placement: ThreadHostToolSourcePlacement
    ) throws -> ThreadHostToolCreateWorkspace {
        switch requested {
        case .project(let path):
            return .project(path: path)
        case .task(let grantedRoots):
            return .task(grantedRoots: try canonicalGrantedRoots(grantedRoots))
        case .inherit(let grantedRoots):
            switch placement.mode {
            case .task:
                return .task(grantedRoots: try canonicalGrantedRoots(grantedRoots))
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

    /// The model options a requested model and effort validate against. The defaults resolution
    /// only carries the *default* provider's options, so a request naming a different ready
    /// provider asks discovery for that provider's own list — otherwise a valid model on the
    /// non-default provider would be falsely rejected.
    func modelOptions(
        for provider: String,
        resolution: ThreadDefaultResolution
    ) async -> [AgentCLIKit.AgentModelOption] {
        if provider == resolution.providerID, !resolution.modelOptions.isEmpty {
            return resolution.modelOptions
        }
        if let providerDiscovery,
           let providerID = AgentCLIKit.AgentProviderID(rawValue: provider) {
            let discovered = await providerDiscovery.modelOptions(for: providerID)
            if !discovered.isEmpty {
                return discovered
            }
        }
        return ThreadDefaultResolver.modelOptions(for: provider, providerStatuses: [:])
    }

    func validatedProvider(
        _ requested: String?,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        guard let requested else {
            guard let providerID = resolution.providerID else {
                throw ThreadHostToolServiceError.noReadyProvider
            }
            return providerID
        }
        guard resolution.readyProviderIDs.contains(requested) else {
            throw ThreadHostToolServiceError.providerNotReady(
                providerID: requested,
                ready: resolution.readyProviderIDs
            )
        }
        return requested
    }

    /// `nil` means "the provider's default model", which is what an omitted `model` inherits from
    /// the user's settings when the provider matches.
    func validatedModel(
        _ requested: String?,
        options: [AgentCLIKit.AgentModelOption],
        resolution: ThreadDefaultResolution,
        provider: String
    ) throws -> String? {
        guard let requested else {
            return provider == resolution.providerID ? resolution.storedThreadModel : nil
        }
        guard let option = AgentModelOptionSelection.option(in: options, matching: requested) else {
            throw ThreadHostToolServiceError.modelUnavailable(model: requested)
        }
        let stored = AgentModelOptionSelection.storedModelValue(for: option)
        return stored == AppSettings.defaultModelValue ? nil : stored
    }

    func validatedEffort(
        _ requested: String?,
        options: [AgentCLIKit.AgentModelOption],
        model: String?,
        resolution: ThreadDefaultResolution,
        provider: String
    ) throws -> String {
        guard let requested else {
            let inherited = provider == resolution.providerID ? resolution.effort : AppSettings.defaultEffortLevel
            return AgentModelOptionSelection.normalizedEffort(inherited, options: options, selectedModel: model)
        }
        let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: model)
        guard supported.isEmpty || supported.contains(where: { $0.value == requested }) else {
            throw ThreadHostToolServiceError.effortUnavailable(
                effort: requested,
                supported: supported.map(\.value)
            )
        }
        return requested
    }

    func validatedPermissionMode(
        _ requested: String?,
        provider: String,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        let supported = AppSettings.supportedPermissionModes(forProvider: provider)
        guard let requested else {
            let inherited = provider == resolution.providerID ? resolution.permissionMode : ""
            return supported.contains(inherited)
                ? inherited
                : AppSettings.defaultPermissionMode(forProvider: provider)
        }
        guard supported.contains(requested) else {
            throw ThreadHostToolServiceError.permissionModeUnavailable(
                mode: requested,
                providerID: provider,
                supported: supported
            )
        }
        return requested
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
    let dispatchedInitialPrompt: Bool

    var message: String {
        var message = "Created the thread \"\(name)\" \(workspaceSummary) (id: \(threadID)) using \(provider), " +
            "model \(model ?? AppSettings.defaultModelValue), effort \(effort), permissions \(permissionMode)"
        message += isPinned ? ", pinned." : "."
        if case .task(let grantedRoots) = workspace, !grantedRoots.isEmpty {
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
        case .task(let grantedRoots):
            content["granted_roots"] = .array(grantedRoots.map(AgentCLIKit.JSONValue.string))
        }
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }

    private var workspaceSummary: String {
        switch workspace {
        case .project(let path):
            "in \(path)"
        case .task:
            "in its own private workspace"
        }
    }
}
