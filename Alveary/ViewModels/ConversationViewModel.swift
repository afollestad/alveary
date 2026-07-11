import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ConversationViewModel {
    let conversation: Conversation

    private(set) var state: ConversationState
    var hasActivatedViewLifecycle = false
    var hasEverActivatedViewLifecycle = false
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
    let attachmentStore: any ConversationAttachmentStore
    let threadActivityRecorder: any ThreadActivityRecording
    var subscriptionTask: Task<Void, Never>?
    static let maxRespawnAttempts = 2
    var saveTask: Task<Void, Never>?
    var saveTaskID: UUID?
    var needsFollowUpSave = false
    var initialSetupTask: Task<Void, Error>?
    var queueDrainTask: Task<Void, Never>?
    @ObservationIgnored var composerDraftSnapshotProvider: ComposerDraftSnapshotProvider?
    @ObservationIgnored var promptDismissalsResolving: Set<String> = []
    @ObservationIgnored var promptDismissalFalloutSuppressionActive = false
    @ObservationIgnored var promptDismissalNewOutboundTurnStarted = false
    @ObservationIgnored var promptDismissalTerminalFalloutSeen = false
    @ObservationIgnored var promptDismissalDelayedFalloutStarted = false
    @ObservationIgnored var promptDismissalSuppressedApprovals: [ToolApprovalRequest] = []
    @ObservationIgnored var promptDismissalHandledApprovalKeys: Set<ClaudeToolApprovalKey> = []
    @ObservationIgnored var commitMessageGenerationContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored var draftMaterializationSaver: () throws -> Void

    var streamingText: String? { state.streamingText }
    var thoughtText: String? { state.thoughtText }
    var thoughtSequence: Int { state.thoughtSequence }
    var completedThoughtText: String? { state.completedThoughtText }
    var completedThoughtSequence: Int { state.completedThoughtSequence }

    var isAgentActivelyWorking: Bool {
        state.turnState.isActive || agentsManager.status(for: conversation.id) == .busy
    }

    var providerCanSteerCurrentTurn: Bool {
        let providerId = conversation.provider ?? settingsService.current.defaultProvider
        if providerId == "codex" {
            return state.turnState.isActive && state.activeRuntimeActivityTurnId != nil
        }
        return isAgentActivelyWorking
    }

    var canSteerCurrentTurn: Bool {
        !state.isNormalSteeringBlockedBySessionHandoff && providerCanSteerCurrentTurn
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
        contextWindowCache: any ContextWindowCache,
        attachmentStore: any ConversationAttachmentStore = DefaultConversationAttachmentStore(),
        threadActivityRecorder: any ThreadActivityRecording = NoopThreadActivityRecorder(),
        draftMaterializationSaver: (() throws -> Void)? = nil
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
        self.attachmentStore = attachmentStore
        self.threadActivityRecorder = threadActivityRecorder
        self.draftMaterializationSaver = draftMaterializationSaver ?? { try modelContext.save() }
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
        cleanupUnreferencedImageAttachments()
    }

    var needsSetup: Bool {
        !(dbThread()?.hasCompletedInitialSetup ?? true)
    }

    func startAgent(config: AgentSpawnConfig) async throws {
        try await withOutboundReservation {
            try await startAgentReserved(config: config)
        }
    }

    func steer(_ message: String, supportsLocalImageInput: Bool = true) async throws {
        guard !state.isNormalSteeringBlockedBySessionHandoff else {
            throw AgentError.spawnFailed("Session handoff is in progress")
        }
        guard providerCanSteerCurrentTurn else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }

        let outbound = try OutboundMessageText(visibleText: message).resolvingImageAttachments(
            state.stagedImageAttachments,
            supportsLocalImageInput: supportsLocalImageInput,
            fallbackText: fallbackText(visibleText:attachments:)
        ).resolvingFileAttachments(
            state.stagedFileAttachments,
            fallbackText: fallbackText(visibleText:fileAttachments:)
        ).resolvingAppShots(
            state.stagedAppShots,
            providerID: conversation.provider ?? settingsService.current.defaultProvider
        )
        try await ensureAppShotProviderPrerequisites(appShots: outbound.appShots)

        try await withOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }

            let localMessage = prepareVisibleSteeringAttempt(outbound, in: dbConversation)
            do {
                try await sendVisibleSteeringMessage(
                    outbound.transportText ?? outbound.visibleText,
                    steeringInputID: localMessage.id,
                    attachments: outbound.attachments,
                    providerMetadata: outbound.providerMetadata
                )
                markVisibleTurnStarted()
                state.turnState.beginTurn()
                state.clearRetryableFailedMessage(id: localMessage.id)
                state.markTranscriptImageAttachments(id: localMessage.id, attachments: outbound.attachments)
                state.markTranscriptFileAttachments(id: localMessage.id, attachments: outbound.consumedFileAttachments)
                state.markTranscriptAppShots(id: localMessage.id, appShots: outbound.appShots)
            } catch {
                state.markRetryableFailedMessage(
                    id: localMessage.id,
                    stagedContext: nil,
                    transportText: outbound.transportText,
                    attachments: outbound.attachments,
                    fileAttachments: outbound.consumedFileAttachments,
                    appShots: outbound.appShots,
                    providerMetadata: outbound.providerMetadata
                )
                state.lastTurnError = "Steer failed: \(error.localizedDescription)"
                throw error
            }
        }
    }

    private func prepareVisibleSteeringAttempt(
        _ outbound: OutboundMessageText,
        in dbConversation: Conversation
    ) -> ConversationEventRecord {
        let localMessage = insertLocalUserMessage(
            outbound.visibleText,
            into: dbConversation,
            imageAttachments: outbound.attachments,
            fileAttachments: outbound.consumedFileAttachments,
            appShots: outbound.appShots
        )
        clearStagedImageAttachmentsIfTheyMatch(outbound.consumedAttachments)
        clearStagedFileAttachmentsIfTheyMatch(outbound.consumedFileAttachments)
        clearStagedAppShotsIfTheyMatch(outbound.consumedAppShots)
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.activeRuntimeActivityTurnId = nil
        return localMessage
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
        hydrateGoalState(from: events)
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
        clearQueuedMessagesPauseIfQueueEmpty()
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
        restoreExitPlanModeRevisionGuidanceIfNeeded(removed.consumedExitPlanModeRevisionGuidance)

        appendToInputDraft(removed.text)
        clearQueuedMessagesPauseIfQueueEmpty()
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
        let previousState = self.state
        previousState.inputDraftPublishTask?.cancel()
        previousState.inputDraftPublishTask = nil
        previousState.hasPendingBlockInputDocumentChange = false
        if previousState !== state {
            state.inputDraftPublishTask?.cancel()
            state.inputDraftPublishTask = nil
            state.hasPendingBlockInputDocumentChange = false
            if hasActivatedViewLifecycle {
                previousState.unregisterViewMount()
                state.registerViewMount()
            }
        }
        self.state = state
        runtimeStore.bindConversationState(state, for: conversation.id)
    }

    isolated deinit {
        if hasActivatedViewLifecycle {
            state.unregisterViewMount()
        }
        state.inputDraftPublishTask?.cancel()
        state.inputDraftPublishTask = nil
        state.hasPendingBlockInputDocumentChange = false
        queueDrainTask?.cancel()
        queueDrainTask = nil
        if let activeKeepAwakeSource {
            keepAwakeService.setActive(false, for: activeKeepAwakeSource)
        }
    }
}

extension ConversationViewModel {
    var turnState: TurnState { state.turnState }
    var messageQueue: MessageQueue { state.messageQueue }
}

extension ConversationViewModel {
    func userMessageRecord(id: String) -> ConversationEventRecord? {
        try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
    }
}
