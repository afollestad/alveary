import AgentCLIKit
import Foundation
import SwiftData

/// Settings a new project thread starts with. `name` omitted keeps the placeholder title so
/// provider auto-naming still applies; `pinned` requests a sidebar pin inside the creating save.
struct ProjectThreadSeed {
    let provider: String
    let permissionMode: String
    let model: String?
    let effort: String
    let isDraft: Bool
    let name: String?
    let pinned: Bool

    init(
        provider: String,
        permissionMode: String,
        model: String?,
        effort: String,
        isDraft: Bool,
        name: String? = nil,
        pinned: Bool = false
    ) {
        self.provider = provider
        self.permissionMode = permissionMode
        self.model = model
        self.effort = effort
        self.isDraft = isDraft
        self.name = name
        self.pinned = pinned
    }
}

/// App-scoped thread creation and archiving.
///
/// `SidebarViewModel` is per-window, so callers with no window — the `alveary_host` MCP tools —
/// cannot route through it. This service owns the durable half of those lifecycles (persistence,
/// runtime teardown, provider-session actions, notifications) and returns what the sidebar needs
/// to finish the UI half; `SidebarViewModel` delegates rather than keeping a second copy.
/// Drafts, task threads, restore, delete, fork, and selection routing stay view-side.
@MainActor
final class ThreadLifecycleService {
    typealias ScheduledTaskRunQuiescence = @MainActor (PersistentIdentifier) async throws -> Void

    let modelContext: ModelContext
    private let settingsService: SettingsService
    private let agentsManager: any AgentsManager
    // Reached from `ThreadLifecycleService+Archive.swift`.
    let providerSessionActionService: any ProviderSessionActionService
    let notificationManager: any NotificationManager
    private let invalidateConversationController: @MainActor (String) -> Void
    private let stopAndWaitForScheduledTaskRun: ScheduledTaskRunQuiescence
    private let saveThreadCreation: @MainActor (ModelContext) throws -> Void

    init(
        modelContext: ModelContext,
        settingsService: SettingsService,
        agentsManager: any AgentsManager,
        providerSessionActionService: any ProviderSessionActionService = NoopProviderSessionActionService(),
        notificationManager: any NotificationManager,
        invalidateConversationController: @escaping @MainActor (String) -> Void = { _ in },
        stopAndWaitForScheduledTaskRun: @escaping ScheduledTaskRunQuiescence = { _ in },
        saveThreadCreation: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.agentsManager = agentsManager
        self.providerSessionActionService = providerSessionActionService
        self.notificationManager = notificationManager
        self.invalidateConversationController = invalidateConversationController
        self.stopAndWaitForScheduledTaskRun = stopAndWaitForScheduledTaskRun
        self.saveThreadCreation = saveThreadCreation
    }

    func insertProjectThread(projectPath: String, seed: ProjectThreadSeed) throws -> AgentThread {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == projectPath
        })
        guard let project = try modelContext.fetch(descriptor).first else {
            throw SidebarViewModelError.projectMissing
        }
        return try insertProjectThread(project: project, seed: seed)
    }

    func insertProjectThread(project: Project, seed: ProjectThreadSeed) throws -> AgentThread {
        // Unrelated pending edits must reach the store before a failed insert rolls the context back.
        if modelContext.hasChanges {
            try modelContext.save()
        }
        let thread = AgentThread(
            name: seed.name ?? "New thread",
            hasCustomName: seed.name != nil,
            permissionMode: seed.permissionMode,
            effort: seed.effort,
            model: seed.model,
            useWorktree: settingsService.current.createWorktreeByDefault && project.isGitRepository,
            isDraft: seed.isDraft,
            project: project
        )
        thread.mode = .project
        let conversation = Conversation(
            provider: seed.provider,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )

        modelContext.insert(thread)
        modelContext.insert(conversation)
        do {
            // A pinned project already absorbs its children, so the pin would be invisible and
            // normalization would clear it in the same commit.
            if seed.pinned, !project.isPinned {
                try SidebarPinOrdering.pin(thread, in: modelContext)
            }
            try saveThreadCreation(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        return thread
    }

    func requireThread(id: PersistentIdentifier) throws -> AgentThread {
        guard let thread = modelContext.resolveThread(id: id) else {
            throw SidebarViewModelError.threadMissing
        }
        return thread
    }

    func scheduledTaskAttachmentError(for thread: AgentThread) -> SidebarViewModelError? {
        if let definition = thread.blockingScheduledTaskAttachment {
            return .scheduledTaskAttachment(definition.title)
        }
        if thread.hasBlockingScheduledTaskRunAttachment {
            return .activeScheduledTaskRunAttachment
        }
        return nil
    }

    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        if let error = scheduledTaskAttachmentError(for: thread) {
            throw error
        }
    }

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread) async throws -> AgentThread {
        let threadID = thread.persistentModelID
        guard let run = thread.scheduledTaskRun else {
            return thread
        }
        let runID = run.persistentModelID

        try await stopAndWaitForScheduledTaskRun(runID)

        guard let currentThread = modelContext.resolveThread(id: threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        if let currentRun = currentThread.scheduledTaskRun,
           !currentRun.hasKnownTerminalStatus {
            throw SidebarViewModelError.scheduledTaskRunStillActive
        }
        return currentThread
    }

    func makeThreadArchiveSnapshot(_ thread: AgentThread) throws -> ThreadArchiveSnapshot {
        let dbThread = try requireThread(id: thread.persistentModelID)
        let threadID = dbThread.persistentModelID
        return ThreadArchiveSnapshot(
            threadID: threadID,
            mode: dbThread.effectiveMode,
            conversationIDs: liveConversationIDs(for: threadID),
            providerSessionAction: providerSessionActionSnapshot(for: dbThread)
        )
    }

    func providerSessionActionSnapshot(for thread: AgentThread) -> ProviderSessionActionSnapshot {
        let threadID = thread.persistentModelID
        let workingDirectory = thread.primaryWorkingDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return ProviderSessionActionSnapshot(
            conversations: liveConversations(for: threadID).map {
                ProviderSessionConversationSnapshot(
                    conversationID: $0.id,
                    providerID: $0.provider,
                    providerSessionID: $0.providerSessionId,
                    providerSessionProviderID: $0.providerSessionProviderId,
                    providerSessionWorkingDirectory: $0.providerSessionWorkingDirectory
                )
            },
            workingDirectory: workingDirectory
        )
    }

    func liveConversationIDs(for threadID: PersistentIdentifier) -> [String] {
        liveConversations(for: threadID).map(\.id)
    }

    func invalidateConversationControllers(_ conversationIDs: [String]) {
        for conversationID in conversationIDs {
            invalidateConversationController(conversationID)
        }
    }

    func postThreadLifecycleChanged(threadID: PersistentIdentifier, mode: AgentThreadMode) {
        NotificationCenter.default.post(
            name: .threadLifecycleChanged,
            object: nil,
            userInfo: [
                ThreadLifecycleNotificationKey.threadID: threadID,
                ThreadLifecycleNotificationKey.mode: mode.rawValue
            ]
        )
    }

    func backfillProviderSessionBindings(from records: [AgentCLIKit.AgentSessionRecord]) throws {
        guard !records.isEmpty else {
            return
        }

        for record in records {
            guard let conversation = modelContext.resolveConversation(conversationID: record.conversationId.rawValue) else {
                continue
            }
            conversation.providerSessionId = record.providerSessionId.rawValue
            conversation.providerSessionProviderId = record.providerId.rawValue
            conversation.providerSessionWorkingDirectory = record.workingDirectory?.path
        }
        try modelContext.save()
    }

    func beginConversationTeardowns(_ conversationIDs: [String]) async {
        for conversationId in uniqueConversationIDs(conversationIDs) {
            await agentsManager.kill(conversationId: conversationId)
        }
    }

    func conversationTeardownError(_ conversationIDs: [String]) async -> Error? {
        do {
            try await awaitConversationTeardowns(conversationIDs)
            return nil
        } catch {
            return error
        }
    }

    func awaitConversationTeardowns(_ conversationIDs: [String]) async throws {
        let conversationIDs = uniqueConversationIDs(conversationIDs)
        let agentsManager = agentsManager
        var errors = [Error?](repeating: nil, count: conversationIDs.count)

        await withTaskGroup(of: (Int, Error?).self) { group in
            for (index, conversationId) in conversationIDs.enumerated() {
                group.addTask {
                    do {
                        try await agentsManager.destroyRuntime(conversationId: conversationId)
                        return (index, nil)
                    } catch { return (index, error) }
                }
            }

            for await (index, error) in group {
                errors[index] = error
            }
        }

        if let firstError = errors.compactMap({ $0 }).first {
            throw firstError
        }
    }

    func uniqueConversationIDs(_ conversationIDs: [String]) -> [String] {
        var seen = Set<String>()
        return conversationIDs.filter { seen.insert($0).inserted }
    }

    private func liveConversations(for threadID: PersistentIdentifier) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
