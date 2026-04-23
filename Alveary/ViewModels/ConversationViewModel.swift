import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationViewModel {
    let conversation: Conversation

    private(set) var state: ConversationState
    private var hasActivatedViewLifecycle = false

    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let modelContext: ModelContext
    let conversationModelID: PersistentIdentifier
    let settingsService: SettingsService
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    var subscriptionTask: Task<Void, Never>?
    static let maxRespawnAttempts = 2
    var saveTask: Task<Void, Never>?
    var saveTaskID: UUID?
    var needsFollowUpSave = false
    var initialSetupTask: Task<Void, Error>?

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
    }

    func activateViewLifecycle() {
        guard !hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = true
        hydratePendingRestoreContextIfNeeded()
        hydratePendingToolApprovalIfNeeded()
        subscribe()
    }

    func deactivateViewLifecycle() {
        guard hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
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
            return
        }

        guard needsSetup else {
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
            return
        }

        // Wrap the initial-setup path in an unstructured Task so `cancel()` can abort it
        // (and trigger the existing rollback) even though the setup phase predates the turn.
        let task = Task { [self] in
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
        }
        initialSetupTask = task
        defer { initialSetupTask = nil }
        try await task.value
    }

    func steer(_ message: String) async throws {
        guard state.turnState.isActive else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }

        try await withOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }

            state.lastTurnInterrupted = false
            state.isCancellingTurn = false
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
        guard state.pendingToolApproval == nil else {
            throw AgentError.spawnFailed("Approve or deny the pending tool use before applying session changes")
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

    func editQueuedMessage(id: UUID) {
        guard state.inFlightQueuedMessageID != id,
              let removed = state.messageQueue.remove(id: id) else {
            return
        }

        if let restoredContext = removed.stagedContext,
           state.stagedContext == nil,
           !state.messageQueue.pending.contains(where: { $0.stagedContext != nil }) {
            state.stagedContext = restoredContext
        }

        if state.inputDraft.isEmpty {
            state.inputDraft = removed.text
        } else {
            state.inputDraft += "\n\n" + removed.text
        }
    }

    func retryFailedUserMessage(id: String) async throws {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before retrying the message")
        }
        guard state.retryableFailedMessageIDs.contains(id) else {
            return
        }
        guard let record = userMessageRecord(id: id),
              let message = record.content,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.clearRetryableFailedMessage(id: id)
            return
        }

        do {
            try await withOutboundReservation {
                try await deliverMessageReserved(
                    message,
                    stagedContextOverride: state.retryableFailedMessageStagedContexts[id],
                    existingLocalUserMessageID: id
                )
            }
        } catch {
            state.lastTurnError = "Retry failed: \(error.localizedDescription)"
            throw error
        }
    }

    func cancel() async {
        if let task = initialSetupTask {
            initialSetupTask = nil
            // Flip the UI into a dedicated cancelling state so the stop button is replaced
            // by a spinner until the rollback completes.
            state.isCancellingInitialSetup = true
            task.cancel()
            _ = try? await task.value
            // Rollback's `restoreStateAfterFailedInitialSetup` replaces the state snapshot but
            // does not touch this flag, so clear it here on whichever state the view model now
            // observes — a no-op on a freshly replaced state, and the UI reset on the retained one.
            state.isCancellingInitialSetup = false
            return
        }

        guard state.turnState.isActive else {
            return
        }

        state.isCancellingTurn = true
        await agentsManager.cancelTurn(conversationId: conversation.id)
    }

    func dismissStagedContext() {
        let dismissedContext = state.stagedContext
        state.stagedContext = nil

        guard let dismissedContext,
              let dbConversation = dbConversation(),
              dbConversation.pendingRestoreContext == dismissedContext else {
            return
        }

        dbConversation.pendingRestoreContext = nil
        do {
            try modelContext.save()
        } catch {
            // Best-effort only; the user explicitly chose to drop the restore context.
        }
    }

    func replaceState(with state: ConversationState) {
        self.state = state
    }

    deinit {}
}

private extension ConversationViewModel {
    func userMessageRecord(id: String) -> ConversationEventRecord? {
        try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }
}
