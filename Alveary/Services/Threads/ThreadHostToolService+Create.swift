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
        let request = try await validatedCreateRequest(parsed, placement: placement, defaults: defaults)
        try Task.checkCancellation()
        // Discovery may leave unrelated edits pending; receipt maintenance must not roll them back.
        try flushPendingChanges()
        if let receipt = try replayedReceipt(
            on: try resolveSource(context: context).conversation, deduplicationKey: deduplicationKey,
            processToken: context.processToken, at: requestDate
        ) { return replayedCreateResult(receipt: receipt) }
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
                createdAt: requestDate,
                structuredResult: insertion.created.result.structuredContent
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
                projectName: thread.project?.name,
                dispatchedInitialPrompt: request.initialPrompt != nil
            )
        )
    }

    /// Read from the inserted row rather than the request, so the reported section is the
    /// membership the thread actually got — a Project thread reports none at all, and a thread
    /// created pinned reports the section it returns to on unpin.
    func createdSectionName(for thread: AgentThread) -> String? {
        guard thread.project == nil else {
            return nil
        }
        return thread.customSection?.name ?? SidebarSectionKind.tasks.builtinDisplayName
    }

    func insertThread(_ request: ThreadHostToolCreateRequest) throws -> AgentThread {
        let workspace = request.workspace
        if let source = workspace.snapshot.primarySource {
            let project = workspace.projectID.flatMap(modelContext.resolveProject(projectID:))
            if let id = workspace.projectID, project == nil { throw ThreadHostToolServiceError.projectNotRegistered(path: id) }
            _ = try WorkspaceFolderTarget(directory: source.path, source: source, isPrimary: true).requireDirectory()
            return try lifecycleService.insertSourceThread(
                project: project,
                seed: ProjectThreadSeed(
                    provider: request.provider, permissionMode: request.permissionMode,
                    model: request.model, effort: request.effort, isDraft: false,
                    name: request.name, pinned: request.pinned, workspaceSnapshot: workspace.snapshot,
                    useWorktree: workspace.useWorktree, sectionID: workspace.sectionID
                )
            )
        }
        return try lifecycleService.insertTaskThread(seed: TaskThreadSeed(
            provider: request.provider, permissionMode: request.permissionMode,
            model: request.model, effort: request.effort, isDraft: false, name: request.name, pinned: request.pinned,
            grantedRoots: workspace.snapshot.grants.map(\.path),
            placement: workspace.placement, workspaceSnapshot: workspace.snapshot
        ))
    }

    func replayedCreateResult(receipt: ThreadHostToolReceipt) -> AgentCLIKit.AgentHostToolResult {
        if let content = receipt.structuredResult {
            return AgentCLIKit.AgentHostToolResult(text: receipt.message, structuredContent: content)
        }
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
    ) async throws -> ThreadHostToolCreateRequest {
        let model = try validatedModel(parsed.model, defaults: defaults)
        let effort = try validatedEffort(parsed.effort, defaults: defaults, model: model)
        let permissionMode = try validatedPermissionMode(
            parsed.permissionMode,
            provider: defaults.provider,
            resolution: defaults.resolution
        )
        return ThreadHostToolCreateRequest(
            workspace: try await validatedWorkspace(parsed.workspace, placement: placement),
            name: parsed.name,
            provider: defaults.provider,
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            initialPrompt: parsed.initialPrompt,
            pinned: parsed.pinned ?? false
        )
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
    let projectName: String?
    let dispatchedInitialPrompt: Bool

    var message: String {
        var message = "Created the thread \"\(name)\" \(workspaceSummary) (id: \(threadID)) using \(provider), " +
            "model \(model ?? AppSettings.defaultModelValue), effort \(effort), permissions \(permissionMode)"
        message += isPinned ? ", pinned." : "."
        if let projectName { message += " It is shown under \(projectName)." }
        let grants = workspace.snapshot.grants.map(\.path)
        if !grants.isEmpty { message += " It can also reach \(grants.joined(separator: ", "))." }
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
        if let id = workspace.projectID { content["project_id"] = .string(id) }
        if let primary = workspace.snapshot.primarySource {
            content["primary_folder_path"] = .string(primary.path)
            content["project_path"] = .string(primary.path)
        }
        content["granted_roots"] = .array(workspace.snapshot.grants.map { .string($0.path) })
        if let sectionName {
            content["section"] = .string(sectionName)
        }
        return AgentCLIKit.AgentHostToolResult(text: message, structuredContent: .object(content))
    }

    private var workspaceSummary: String {
        if let primary = workspace.snapshot.primarySource { return "using \(primary.path)" }
        return "in its own private workspace"
    }
}
