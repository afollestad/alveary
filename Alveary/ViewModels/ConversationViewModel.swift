import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationViewModel {
    let conversation: Conversation

    private(set) var state: ConversationState
    var hasActivatedViewLifecycle = false
    var activeKeepAwakeSource: KeepAwakeActivitySource?

    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let keepAwakeService: KeepAwakeService
    let modelContext: ModelContext
    let conversationModelID: PersistentIdentifier
    let settingsService: SettingsService
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    var subscriptionTask: Task<Void, Never>?
    static let maxRespawnAttempts = 2
    var saveTask: Task<Void, Never>?
    var saveTaskID: UUID?
    var needsFollowUpSave = false
    var initialSetupTask: Task<Void, Error>?
    @ObservationIgnored var composerDraftSnapshotProvider: ComposerDraftSnapshotProvider?
    @ObservationIgnored var promptDismissalsResolving: Set<String> = []

    var turnState: TurnState { state.turnState }
    var messageQueue: MessageQueue { state.messageQueue }
    var streamingText: String? { state.streamingText }

    var isAgentActivelyWorking: Bool {
        state.turnState.isActive || agentsManager.status(for: conversation.id) == .busy
    }

    var canSteerCurrentTurn: Bool {
        let providerId = conversation.provider ?? settingsService.current.defaultProvider
        if providerId == "codex" {
            return state.turnState.isActive && state.activeRuntimeActivityTurnId != nil
        }
        return isAgentActivelyWorking
    }

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

    var hasUnansweredPrompt: Bool {
        state.grouper.hasUnansweredPrompt
    }

    func canSubmitPromptAnswer(promptId: String) -> Bool {
        guard !state.isSendingMessage,
              !state.isReconfiguringSession else {
            return false
        }
        return !state.turnState.isActive ||
            canAnswerLiveAskUserQuestion(promptId: promptId) ||
            latestUnresolvedAskUserQuestionApprovalCandidate(promptId: promptId) != nil
    }

    init(
        conversation: Conversation,
        agentsManager: any AgentsManager,
        runtimeStore: any ConversationRuntimeStore,
        keepAwakeService: KeepAwakeService,
        modelContext: ModelContext,
        settingsService: SettingsService,
        worktreeManager: WorktreeManager,
        providerSetup: ProviderSetupService,
        contextWindowCache: any ContextWindowCache
    ) {
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.keepAwakeService = keepAwakeService
        self.modelContext = modelContext
        self.conversationModelID = conversation.persistentModelID
        self.settingsService = settingsService
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.contextWindowCache = contextWindowCache
        self.state = runtimeStore.conversationState(for: conversation.id)
        if self.state.runtimePlanModeEnabled == nil {
            self.state.runtimePlanModeEnabled = conversation.thread?.planModeEnabled ?? false
        }
        if self.state.runtimeSpeedMode == nil {
            self.state.runtimeSpeedMode = conversation.thread?.normalizedSpeedMode ?? .standard
        }
        if self.state.lastNonPlanPermissionMode == nil,
           conversation.thread?.permissionMode != "plan" {
            self.state.lastNonPlanPermissionMode = conversation.thread?.permissionMode
        }
    }

    func activateViewLifecycle() {
        guard !hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = true
        hydratePendingRestoreContextIfNeeded()
        hydratePendingToolApprovalIfNeeded()
        subscribe()
        schedulePendingExitPlanModeFollowUpQuietFallbackIfNeeded()
    }

    func deactivateViewLifecycle() {
        guard hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        cancelPendingExitPlanModeFollowUpQuietTaskForViewDeactivation()
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
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try await deliverMessageReserved(message)
        }
    }

    func send(_ message: String, stagedContextOverride: String? = nil) async throws {
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before sending a new one")
        }

        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try await deliverMessageReserved(message, stagedContextOverride: stagedContextOverride)
        }
    }

    func queueOrSend(
        _ message: String,
        requiredPlanModeEnabled: Bool? = nil,
        requiredSpeedMode: AgentSpeedMode? = nil
    ) async throws {
        guard !state.hasActiveSessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard !state.isAwaitingExitPlanModeFollowUp else {
            throw AgentError.spawnFailed("Wait for the plan response to be sent before sending another message")
        }

        if isAgentActivelyWorking || state.isSendingMessage || state.messageQueue.peekNext() != nil {
            state.messageQueue.enqueue(
                message,
                stagedContext: state.stagedContext,
                requiredPlanModeEnabled: requiredPlanModeEnabled,
                requiredSpeedMode: requiredSpeedMode
            )
            state.stagedContext = nil
            return
        }

        guard needsSetup else {
            if let requiredPlanModeEnabled {
                try await ensurePlanModeForOutbound(requiredPlanModeEnabled)
            }
            if let requiredSpeedMode {
                try await ensureSpeedModeForOutbound(requiredSpeedMode)
            }
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
            return
        }

        // Wrap the initial-setup path in an unstructured Task so `cancel()` can abort it
        // (and trigger the existing rollback) even though the setup phase predates the turn.
        let task = Task { [self] in
            if let requiredPlanModeEnabled {
                try await ensurePlanModeForOutbound(requiredPlanModeEnabled)
            }
            if let requiredSpeedMode {
                try await ensureSpeedModeForOutbound(requiredSpeedMode)
            }
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
        }
        initialSetupTask = task
        defer { initialSetupTask = nil }
        try await task.value
    }

    func steer(_ message: String) async throws {
        guard canSteerCurrentTurn else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }

        try await withOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }

            state.lastTurnInterrupted = false
            state.isCancellingTurn = false
            state.lastTurnError = nil
            state.activeRuntimeActivityTurnId = nil
            try await agentsManager.sendMessage(message, conversationId: conversation.id)
            state.turnState.beginTurn()
            insertLocalUserMessage(message, into: dbConversation)
        }
    }

    func answerPrompt(promptId: String, answers: [(question: String, answer: String)]) async throws -> String {
        let approvalCandidate = latestUnresolvedAskUserQuestionApprovalCandidate(promptId: promptId)
        let promptPendingApproval = pendingApprovalForPromptAnswer(promptId: promptId, approvalCandidate: approvalCandidate)
        let canAnswerLivePrompt = canAnswerLiveAskUserQuestion(promptId: promptId) || promptPendingApproval != nil
        guard !state.turnState.isActive || canAnswerLivePrompt,
              !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn to finish before answering the prompt")
        }
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Wait for session changes to finish before answering the prompt")
        }

        let message = Self.formatPromptAnswers(answers: answers)
        let summary = Self.promptSummary(answers: answers)
        let pendingApproval = state.pendingToolApproval

        state.isSendingMessage = true
        defer { state.isSendingMessage = false }

        if let promptPendingApproval {
            if approvalCandidate?.shouldCheckSessionResolution != false,
                let resolvedStatus = clearResolvedToolApprovalFromClaudeSessionIfNeeded(promptPendingApproval.request) {
                if resolvedStatus != .approved {
                    try await deliverMessageReserved(
                        message,
                        useCurrentStagedContextWhenOverrideNil: false,
                        respawnSettingsSource: .currentContinuation
                    )
                }
            } else {
                try await answerDeferredAskUserQuestion(promptPendingApproval, answers: answers)
            }
        } else {
            try await deliverMessageReserved(
                message,
                useCurrentStagedContextWhenOverrideNil: false,
                respawnSettingsSource: .currentContinuation
            )
            supersedePendingToolApprovalAfterPromptAnswer(pendingApproval)
        }

        recordPromptAnswerSummary(promptId: promptId, summary: summary)
        return summary
    }

    func recordPromptHandled(promptId: String) {
        recordPromptAnswerSummary(promptId: promptId, summary: ChatItemGrouper.handledPromptSummary)
    }

    func recordPromptAnswerSummary(promptId: String, summary: String) {
        let conversationID = conversation.id
        let promptEvents = try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate {
                    $0.conversationId == conversationID &&
                        $0.type == "tool_call" &&
                        $0.toolId == promptId &&
                        $0.toolName == "AskUserQuestion"
                },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )

        guard let promptRecord = promptEvents?.last else {
            state.grouper.markPromptAnswered(promptId: promptId, summary: summary)
            return
        }

        promptRecord.content = summary
        do {
            try modelContext.save()
            state.grouper.markPromptAnswered(promptId: promptId, summary: summary)
        } catch {
            state.grouper.markPromptAnswered(promptId: promptId, summary: summary)
        }
    }

    func canAnswerLiveAskUserQuestion(promptId: String) -> Bool {
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status == .pending,
              pendingApproval.request.toolName == "AskUserQuestion",
              pendingApproval.request.toolUseId == promptId else {
            return false
        }
        return true
    }

    func pendingApprovalForPromptAnswer(
        promptId: String,
        approvalCandidate: AskUserQuestionApprovalCandidate?
    ) -> PendingToolApproval? {
        if let approvalCandidate {
            return PendingToolApproval(request: approvalCandidate.request, status: .pending)
        }
        guard let pendingApproval = state.pendingToolApproval,
              pendingApproval.status == .pending,
              pendingApproval.request.toolName == "AskUserQuestion",
              pendingApproval.request.toolUseId == promptId else {
            return nil
        }
        return pendingApproval
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

        appendToInputDraft(removed.text)
    }

    func retryFailedUserMessage(id: String) async throws {
        guard !isAgentActivelyWorking, !state.isSendingMessage else {
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
            try await applyPendingSessionSettingsBeforeNextOutboundTurn()
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

        guard isAgentActivelyWorking else {
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
        self.state.inputDraftPublishTask?.cancel()
        self.state.inputDraftPublishTask = nil
        self.state.hasPendingBlockInputDocumentChange = false
        if self.state !== state {
            state.inputDraftPublishTask?.cancel()
            state.inputDraftPublishTask = nil
            state.hasPendingBlockInputDocumentChange = false
        }
        self.state = state
    }

    isolated deinit {
        state.inputDraftPublishTask?.cancel()
        state.inputDraftPublishTask = nil
        state.hasPendingBlockInputDocumentChange = false
        if let activeKeepAwakeSource {
            keepAwakeService.setActive(false, for: activeKeepAwakeSource)
        }
    }
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
