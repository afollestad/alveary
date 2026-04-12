import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationViewModel {
    let conversation: Conversation

    private(set) var state: ConversationState

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

    func replaceState(with state: ConversationState) {
        self.state = state
    }

    deinit {
        MainActor.assumeIsolated {
            subscriptionTask?.cancel()
            saveTask?.cancel()
        }
    }
}
