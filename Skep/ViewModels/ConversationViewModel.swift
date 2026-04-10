import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationViewModel {
    let conversation: Conversation

    private(set) var state: ConversationState

    private let agentsManager: any AgentsManager
    private let runtimeStore: any ConversationRuntimeStore
    private let modelContext: ModelContext
    private let conversationModelID: PersistentIdentifier
    private let settingsService: SettingsService
    private let worktreeManager: WorktreeManager
    private let providerSetup: ProviderSetupService
    private var subscriptionTask: Task<Void, Never>?
    private static let maxRespawnAttempts = 2
    private var saveTask: Task<Void, Never>?
    private var saveTaskID: UUID?
    private var needsFollowUpSave = false

    var turnState: TurnState { state.turnState }
    var messageQueue: MessageQueue { state.messageQueue }
    var streamingText: String? { state.streamingText }

    var lastTurnError: String? {
        get { state.lastTurnError }
        set { state.lastTurnError = newValue }
    }

    var stagedContext: String? {
        get { state.stagedContext }
        set { state.stagedContext = newValue }
    }

    var sessionContinuityNotice: String? {
        get { state.sessionContinuityNotice }
        set { state.sessionContinuityNotice = newValue }
    }

    var setupPhase: SetupPhase? {
        get { state.setupPhase }
        set { state.setupPhase = newValue }
    }

    init(
        conversation: Conversation,
        agentsManager: any AgentsManager,
        runtimeStore: any ConversationRuntimeStore,
        modelContext: ModelContext,
        settingsService: SettingsService,
        worktreeManager: WorktreeManager,
        providerSetup: ProviderSetupService
    ) {
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.modelContext = modelContext
        self.conversationModelID = conversation.persistentModelID
        self.settingsService = settingsService
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.state = runtimeStore.conversationState(for: conversation.id)
        subscribe()
    }

    var needsSetup: Bool {
        !(dbThread()?.hasCompletedInitialSetup ?? true)
    }

    func startAgent(config: AgentSpawnConfig) async throws {
        try await withOutboundReservation {
            try await startAgentReserved(config: config)
        }
    }

    func setupAndStart(_ message: String) async throws {
        try await withOutboundReservation {
            try await setupAndStartReserved(message)
        }
    }

    func send(_ message: String, stagedContextOverride: String? = nil) async throws {
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before sending a new one")
        }

        try await withOutboundReservation {
            try await deliverMessageReserved(message, stagedContextOverride: stagedContextOverride)
        }
    }

    func queueOrSend(_ message: String) async throws {
        if state.turnState.isActive || state.isSendingMessage || state.messageQueue.peekNext() != nil {
            state.messageQueue.enqueue(message, stagedContext: state.stagedContext)
            state.stagedContext = nil
        } else {
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
        }
    }

    func steer(_ message: String) async throws {
        guard state.turnState.isActive else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }

        try await withOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }

            state.lastTurnError = nil
            try await agentsManager.sendMessage(message, conversationId: conversation.id)
            insertLocalUserMessage(message, into: dbConversation, shouldAutoNameThread: false)
        }
    }

    func answerPrompt(promptId: String, answers: [(question: String, answer: String)]) async throws -> String {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn to finish before answering the prompt")
        }
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before answering the prompt")
        }

        let message = Self.formatPromptAnswers(answers: answers)
        let summary = Self.promptSummary(answers: answers)

        try await withOutboundReservation {
            try await deliverMessageReserved(message)
        }

        let conversationID = conversation.id
        let promptEvents = try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                    $0.type == "tool_call" &&
                    $0.toolId == promptId &&
                    $0.toolName == "AskUserQuestion"
                }
            )
        )

        if let promptRecord = promptEvents?.last {
            promptRecord.content = summary
            do {
                try modelContext.save()
                state.grouper.markPromptAnswered(promptId: promptId, summary: summary)
            } catch {
                // Best-effort only; the live prompt block already updated.
            }
        }

        return summary
    }

    func reconfigureSession(config: AgentSpawnConfig) async throws {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before applying session changes")
        }
        guard !state.isReconfiguringSession else {
            return
        }

        state.isReconfiguringSession = true
        defer { state.isReconfiguringSession = false }

        await flushPendingSaveIfNeeded()
        await prepareForSpawn(config: config)
        try await agentsManager.reconfigureSession(conversationId: conversation.id, config: config)
        state.showPermissionBanner = false
        state.lastPermissionDeniedToolNames = []
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.grouper.resetInFlightStateForNewSession()
        subscribe()
    }

    func reconfigureSession() async throws {
        try await reconfigureSession(config: makeSpawnConfig())
    }

    func rebuildChatItemsIfNeeded(from events: [ConversationEventRecord], forceFullRebuild: Bool = false) {
        state.grouper.update(events: events, forceFullRebuild: forceFullRebuild)
    }

    func removeQueuedMessage(id: UUID) {
        guard state.inFlightQueuedMessageID != id else {
            return
        }

        let removed = state.messageQueue.remove(id: id)
        if let restoredContext = removed?.stagedContext,
           state.stagedContext == nil,
           !state.messageQueue.pending.contains(where: { $0.stagedContext != nil }) {
            state.stagedContext = restoredContext
        }
    }

    func retryNextQueuedMessage() async throws {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before retrying the queued message")
        }
        guard state.inFlightQueuedMessageID == nil else {
            return
        }
        guard let next = state.messageQueue.peekNext() else {
            return
        }

        state.inFlightQueuedMessageID = next.id
        defer {
            if state.inFlightQueuedMessageID == next.id {
                state.inFlightQueuedMessageID = nil
            }
        }

        do {
            try await withOutboundReservation {
                try await deliverMessageReserved(next.text, stagedContextOverride: next.stagedContext)
                state.messageQueue.remove(id: next.id)
                state.respawnAttempts = 0
            }
        } catch {
            state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
            throw error
        }
    }

    func cancel() async {
        await agentsManager.cancelTurn(conversationId: conversation.id)
    }

    deinit {
        MainActor.assumeIsolated {
            subscriptionTask?.cancel()
            saveTask?.cancel()
        }
    }
}

private extension ConversationViewModel {
    func dbConversation() -> Conversation? {
        modelContext.model(for: conversationModelID) as? Conversation
    }

    func dbThread() -> AgentThread? {
        dbConversation()?.thread
    }

    func needsRespawn() async -> Bool {
        guard !needsSetup else {
            return false
        }
        return !(await agentsManager.isRunning(conversationId: conversation.id))
    }

    func repairMissingWorktreeIfNeeded() throws {
        guard let thread = dbThread(),
              thread.useWorktree,
              thread.hasCompletedInitialSetup,
              let worktreePath = thread.worktreePath,
              !FileManager.default.fileExists(atPath: worktreePath) else {
            return
        }

        if let branch = thread.branch,
           !thread.pendingCleanupBranches.contains(branch) {
            thread.pendingCleanupBranches.append(branch)
        }
        thread.branch = nil
        thread.worktreePath = nil
        thread.hasCompletedInitialSetup = false
        try modelContext.save()
    }

    func makeSpawnConfig(
        workingDirectory overrideWorkingDirectory: String? = nil,
        initialPrompt: String? = nil
    ) throws -> AgentSpawnConfig {
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        let providerId = dbConversation.provider ?? settingsService.current.defaultProvider
        let workingDirectory = overrideWorkingDirectory
            ?? dbConversation.thread?.worktreePath
            ?? dbConversation.thread?.project?.path

        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AgentError.spawnFailed("Cannot spawn agent: no working directory")
        }

        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: dbConversation.thread?.permissionMode,
            model: state.selectedModel,
            effort: dbConversation.thread?.effort,
            initialPrompt: initialPrompt
        )
    }

    func prepareForSpawn(config: AgentSpawnConfig) async {
        let shouldAutoTrust = settingsService.current.autoTrustWorktrees && (dbThread()?.useWorktree ?? false)
        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: shouldAutoTrust
        )
    }

    func withOutboundReservation<T>(_ body: () async throws -> T) async throws -> T {
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied")
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Another message is already being sent")
        }

        state.isSendingMessage = true
        defer { state.isSendingMessage = false }
        return try await body()
    }

    func startAgentReserved(config: AgentSpawnConfig) async throws {
        await prepareForSpawn(config: config)
        try await agentsManager.spawn(id: conversation.id, config: config)
        subscribe()
    }

    func deliverMessageReserved(
        _ message: String,
        stagedContextOverride: String? = nil
    ) async throws {
        try repairMissingWorktreeIfNeeded()

        if needsSetup {
            try await setupAndStartReserved(message, stagedContextOverride: stagedContextOverride)
            return
        }

        if await needsRespawn() {
            try await startAgentReserved(config: makeSpawnConfig())
            state.respawnAttempts = 0
        }

        try await sendReserved(message, stagedContextOverride: stagedContextOverride)
    }

    func setupAndStartReserved(
        _ message: String,
        stagedContextOverride: String? = nil
    ) async throws {
        state.lastTurnError = nil

        guard let dbConversation = dbConversation(),
              let thread = dbConversation.thread,
              let project = thread.project else {
            throw AgentError.spawnFailed("No project associated with this thread")
        }

        let workingDirectory = try await createInitialWorkingDirectory(
            for: thread,
            project: project,
            message: message
        )

        setupPhase = .startingAgent
        do {
            try await startAgentReserved(config: makeSpawnConfig(workingDirectory: workingDirectory))
            thread.hasCompletedInitialSetup = true
            try modelContext.save()
            try await sendReserved(message, stagedContextOverride: stagedContextOverride)
        } catch {
            try await rollbackFailedInitialSetup(
                error: error,
                project: project,
                thread: thread,
                preservedDraft: message,
                preservedSelectedModel: state.selectedModel,
                preservedStagedContext: state.stagedContext
            )
            throw error
        }

        setupPhase = nil
    }

    func createInitialWorkingDirectory(
        for thread: AgentThread,
        project: Project,
        message: String
    ) async throws -> String {
        guard thread.useWorktree else {
            return project.path
        }

        setupPhase = .creatingWorktree
        let worktreeSlug = Self.threadName(from: message) ?? thread.name

        do {
            let info = try await worktreeManager.create(
                projectPath: project.path,
                threadName: worktreeSlug,
                baseRef: project.baseRef,
                remoteName: project.remoteName
            )
            thread.worktreePath = info.path
            thread.branch = info.branch
            try modelContext.save()
            return info.path
        } catch {
            if let path = thread.worktreePath {
                do {
                    try await worktreeManager.remove(
                        projectPath: project.path,
                        worktreePath: path,
                        branch: thread.branch
                    )
                    thread.worktreePath = nil
                    thread.branch = nil
                    try modelContext.save()
                } catch {
                    state.lastTurnError =
                        "Initial worktree setup failed and rollback cleanup/metadata clear also failed: " +
                        error.localizedDescription
                }
            }
            setupPhase = nil
            throw error
        }
    }

    func rollbackFailedInitialSetup(
        error: Error,
        project: Project,
        thread: AgentThread,
        preservedDraft: String,
        preservedSelectedModel: String?,
        preservedStagedContext: String?
    ) async throws {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
        needsFollowUpSave = false

        do {
            try await agentsManager.destroyRuntime(conversationId: conversation.id)
        } catch let cleanupError {
            state.lastTurnError =
                "Initial setup failed: \(error.localizedDescription). Runtime cleanup also failed: " +
                cleanupError.localizedDescription
            setupPhase = nil
            throw AgentError.spawnFailed(state.lastTurnError ?? cleanupError.localizedDescription)
        }

        state = runtimeStore.conversationState(for: conversation.id)
        state.inputDraft = preservedDraft
        state.selectedModel = preservedSelectedModel
        state.stagedContext = preservedStagedContext
        thread.hasCompletedInitialSetup = false

        if thread.useWorktree, let path = thread.worktreePath {
            do {
                try await worktreeManager.remove(
                    projectPath: project.path,
                    worktreePath: path,
                    branch: thread.branch
                )
                thread.worktreePath = nil
                thread.branch = nil
                try modelContext.save()
            } catch {
                thread.hasCompletedInitialSetup = true
                do {
                    try modelContext.save()
                    state.lastTurnError =
                        "Initial setup failed and rollback worktree cleanup also failed: " +
                        "\(error.localizedDescription). The existing worktree was preserved, " +
                        "so retry will reuse it instead of creating a second worktree."
                } catch {
                    state.lastTurnError =
                        "Initial setup failed, rollback cleanup failed, and preserved thread metadata " +
                        "could not be saved: \(error.localizedDescription)"
                }
            }
        } else {
            do {
                try modelContext.save()
            } catch {
                state.lastTurnError = "Initial spawn failed and rollback metadata reset also failed: \(error.localizedDescription)"
            }
        }

        setupPhase = nil
    }

    func subscribe() {
        subscriptionTask?.cancel()
        let token = UUID()
        state.activeSubscriptionToken = token
        subscriptionTask = Task { @MainActor in
            guard let subscription = await agentsManager.subscribe(
                conversationId: conversation.id,
                afterIndex: state.lastPersistedEventIndex
            ) else {
                guard state.activeSubscriptionToken == token else {
                    return
                }
                state.activeBufferGeneration = nil
                return
            }

            guard state.activeSubscriptionToken == token else {
                return
            }
            state.activeBufferGeneration = subscription.generation

            for await event in subscription.stream {
                guard state.activeSubscriptionToken == token else {
                    return
                }
                state.lastObservedEventIndex += 1
                handleEvent(event)
            }

            guard !Task.isCancelled, state.activeSubscriptionToken == token else {
                return
            }
            state.turnState.endTurn()
            state.clearStreamingText()
        }
    }

    func handleTurnCompleted() {
        guard state.messageQueue.peekNext() != nil else {
            state.turnState.endTurn()
            return
        }

        Task { @MainActor in
            guard state.inFlightQueuedMessageID == nil else {
                return
            }
            guard let next = state.messageQueue.peekNext() else {
                state.turnState.endTurn()
                return
            }

            state.inFlightQueuedMessageID = next.id
            defer {
                if state.inFlightQueuedMessageID == next.id {
                    state.inFlightQueuedMessageID = nil
                }
            }

            do {
                try await withOutboundReservation {
                    if await needsRespawn() {
                        guard state.respawnAttempts < Self.maxRespawnAttempts else {
                            state.lastTurnError = "Agent process keeps crashing — queued message paused"
                            state.respawnAttempts = 0
                            state.turnState.endTurn()
                            return
                        }
                        state.respawnAttempts += 1
                    }

                    try await deliverMessageReserved(next.text, stagedContextOverride: next.stagedContext)
                    state.messageQueue.remove(id: next.id)
                    state.respawnAttempts = 0
                }
            } catch {
                state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
                state.turnState.endTurn()
            }
        }
    }

    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        shouldAutoNameThread: Bool
    ) {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: "message",
            role: "user",
            content: message,
            conversation: dbConversation
        )
        modelContext.insert(record)
        state.grouper.appendLocalUserMessage(id: record.id, text: message)

        if shouldAutoNameThread,
           settingsService.current.autoGenerateNames,
           dbConversation.thread?.name == "New thread",
           let name = Self.threadName(from: message) {
            dbConversation.thread?.name = name
        }

        scheduleSave()
    }

    func sendReserved(_ message: String, stagedContextOverride: String? = nil) async throws {
        let transportMessage: String
        if let context = stagedContextOverride ?? state.stagedContext {
            transportMessage = context + "\n\n" + message
        } else {
            transportMessage = message
        }

        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        state.lastTurnError = nil
        try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
        if stagedContextOverride == nil {
            state.stagedContext = nil
        }
        state.turnState.beginTurn()
        insertLocalUserMessage(message, into: dbConversation, shouldAutoNameThread: true)
    }

    func handleEvent(_ event: ConversationEvent) {
        switch event {
        case .messageChunk(let text, let parentToolUseId):
            guard parentToolUseId == nil else {
                return
            }
            state.appendStreamingChunk(text)
            return

        case .message(let role, _, _) where role == "user":
            return

        case .message(let role, _, _) where role == "assistant":
            state.clearStreamingText()

        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            state.clearStreamingText()
            if isError {
                state.lastTurnError = stopReason ?? "Agent turn failed"
            }
            state.lastPermissionDeniedToolNames = Set(permissionDenials.map(\.toolName))
            state.showPermissionBanner = !permissionDenials.isEmpty
            if !isError && permissionDenials.isEmpty {
                handleTurnCompleted()
            } else {
                state.turnState.endTurn()
            }

        case .stop:
            state.turnState.endTurn()

        case .subAgentStarted, .subAgentProgress, .subAgentCompleted:
            state.grouper.handleSubAgentControl(event)
            return

        case .notification, .error:
            break

        default:
            break
        }

        guard let dbConversation = dbConversation(),
              let record = event.toRecord(conversation: dbConversation) else {
            return
        }

        modelContext.insert(record)
        scheduleSave()
    }

    func scheduleSave() {
        guard saveTask == nil else {
            needsFollowUpSave = true
            return
        }

        let observedIndexSnapshot = state.lastObservedEventIndex
        let generationSnapshot = state.activeBufferGeneration
        let taskID = UUID()
        saveTaskID = taskID
        saveTask = Task { @MainActor in
            let delayMs = state.turnState.isActive ? 350 : 150

            do {
                try await Task.sleep(for: .milliseconds(delayMs))
                try Task.checkCancellation()
            } catch {
                guard saveTaskID == taskID else {
                    return
                }
                saveTask = nil
                saveTaskID = nil
                return
            }

            do {
                try modelContext.save()

                guard state.activeBufferGeneration == generationSnapshot else {
                    guard saveTaskID == taskID else {
                        return
                    }
                    saveTask = nil
                    saveTaskID = nil
                    return
                }
                guard !Task.isCancelled else {
                    guard saveTaskID == taskID else {
                        return
                    }
                    saveTask = nil
                    saveTaskID = nil
                    return
                }

                state.lastPersistedEventIndex = max(state.lastPersistedEventIndex, observedIndexSnapshot)
                if let generationSnapshot {
                    await agentsManager.markPersisted(
                        conversationId: conversation.id,
                        generation: generationSnapshot,
                        upTo: observedIndexSnapshot
                    )
                }
            } catch {
                // Keep the older persisted cursor so reconnects replay the unsaved tail.
            }

            guard saveTaskID == taskID else {
                return
            }
            saveTask = nil
            saveTaskID = nil
            if needsFollowUpSave {
                needsFollowUpSave = false
                scheduleSave()
            }
        }
    }

    func flushPendingSaveIfNeeded() async {
        guard let saveTask else {
            return
        }
        await saveTask.value
    }
}
