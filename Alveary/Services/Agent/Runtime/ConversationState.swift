import AgentCLIKit
import Foundation
import Observation

enum ComposerDraftSource: Equatable, Sendable {
    case legacyText
    case blockInputMarkdown
}

struct SessionSettingsSnapshot: Equatable, Sendable {
    var model: String?
    var effort: String
    var permissionMode: String
    var planModeEnabled: Bool
    var speedMode: AgentSpeedMode
    var runtimePermissionMode: String?
    var runtimePlanModeEnabled: Bool?
    var runtimeSpeedMode: AgentSpeedMode?
    var lastNonPlanPermissionMode: String?
}

struct PendingSessionSettingsChange: Equatable, Sendable {
    let original: SessionSettingsSnapshot
    var pending: SessionSettingsSnapshot
    var liveSessionConfig: AgentSpawnConfig?
    var invalidatesContextWindow = false

    var hasModelChange: Bool {
        original.model != pending.model
    }

    var hasEffortChange: Bool {
        original.effort != pending.effort
    }

    var hasPermissionModeChange: Bool {
        original.permissionMode != pending.permissionMode
    }

    var hasPlanModeChange: Bool {
        original.planModeEnabled != pending.planModeEnabled
    }

    var hasSpeedModeChange: Bool {
        original.speedMode != pending.speedMode
    }

    var hasAnyChange: Bool {
        hasModelChange || hasEffortChange || hasPermissionModeChange || hasPlanModeChange || hasSpeedModeChange
    }
}

struct PendingExitPlanModeFollowUp: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case awaitingDeniedExitTurn
        case readyToSend
    }

    let toolUseId: String
    let sessionId: String
    let providerId: String
    let providerSessionId: String?
    let message: String
    /// Provider-facing text for the next send; this must never be shown in transcript UI.
    let transportText: String?
    let sourceTurnId: String?
    let sourceSubscriptionToken: UUID?
    let sourceBufferGeneration: UUID?
    let sourceEventIndex: Int
    var lastObservedEventIndex: Int
    var phase: Phase
}

struct PendingExitPlanModeRevisionGuidance: Equatable, Sendable {
    let toolUseId: String
    let sessionId: String
    let providerId: String
    let providerSessionId: String?
}

enum QueuedMessagesPauseReason: Equatable, Sendable {
    case interrupted
}

struct ConversationTerminalBoundary: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case succeeded
        case failed(message: String?)
        case interrupted
    }

    let sequence: UInt64
    let wasVisible: Bool
    let result: Result
}

struct PausedQueueSendConfirmationState: Equatable, Sendable {
    let id: UUID
    let draft: ComposerDraft
    let queuedMessageCount: Int
    var isResolving: Bool

    init(
        id: UUID = UUID(),
        draft: ComposerDraft,
        queuedMessageCount: Int,
        isResolving: Bool = false
    ) {
        self.id = id
        self.draft = draft
        self.queuedMessageCount = queuedMessageCount
        self.isResolving = isResolving
    }
}

@MainActor
@Observable
final class ConversationState {
    let messageQueue = MessageQueue()
    let turnState = TurnState()

    var streamingText: String?
    var streamingTextIsSnapshot = false
    var thoughtText: String?
    var thoughtSequence = 0
    var completedThoughtText: String?
    var completedThoughtSequence = 0
    var lastTurnError: String?
    var lastTurnInterrupted = false
    var controllerTerminalFailureMessage: String?
    private(set) var lastControllerTerminalBoundary: ConversationTerminalBoundary?
    private(set) var hasDeferredControllerTerminalBoundary = false
    var stagedContext: String?
    var sessionContinuityNotice: String?
    var isSendingMessage = false
    var isCancellingTurn = false
    var isCancellingInitialSetup = false
    var isReconfiguringSession = false
    var isHandingOffSession = false
    var isGeneratingCommitMessage = false
    var isDrainingCommitMessageGenerationEvents = false
    var lastObservedEventIndex = 0
    var lastPersistedEventIndex = 0
    var activeBufferGeneration: UUID?
    var activeSubscriptionToken: UUID?
    var activeRuntimeActivityTurnId: String?
    var currentTurnActivityVisibility: AgentTurnActivityVisibility = .hidden
    var hasRecordedLocalTurnEndActivity = false
    var pausedQueueSendConfirmation: PausedQueueSendConfirmationState?
    var inputDraft = ""
    var inputDraftSource: ComposerDraftSource = .legacyText
    var stagedImageAttachments: [LocalImageAttachment] = []
    var stagedFileAttachments: [LocalFileAttachment] = []
    var stagedAppShots: [AppShotAttachment] = []
    @ObservationIgnored private(set) var mountedViewCount = 0
    var inputDraftRevision = 0
    var inputDraftDirtyRevision = 0
    var inputDraftIsEffectivelyEmpty = true
    @ObservationIgnored var hasPendingBlockInputDocumentChange = false
    @ObservationIgnored var inputDraftPublishTask: Task<Void, Never>?
    var isAwaitingHandoffSteering = false
    var handoffSteeringCountdownRemaining: Int?
    var handoffSteeringDraftBaseline: String?
    var sessionHandoffRestorableDraft: String?
    var sessionHandoffRestorableDraftSource: ComposerDraftSource = .legacyText
    var submittedHandoffSteeringPrompt: String?
    var sessionHandoffSteeringCountdownTask: Task<Void, Never>?
    var sessionHandoffStartedInPlanMode = false
    var sessionHandoffNoteRecordID: String?
    var isSessionHandoffSeedTurnActive = false
    var isAutomaticSessionHandoffPending = false
    var hiddenHandoffResponse = ""
    var hiddenCommitMessageResponse = ""
    var pendingHandoffOutput: String?
    var failedSessionHandoffMessage: String?
    var handoffCountdownRemaining: Int?
    var handoffDraftBaseline: String?
    var sessionHandoffCountdownTask: Task<Void, Never>?
    var grouper = ChatItemGrouper()
    var respawnAttempts = 0
    var inFlightQueuedMessageID: UUID?
    var queuedMessagesPauseReason: QueuedMessagesPauseReason?
    var setupPhase: SetupPhase?
    var pendingToolApproval: PendingToolApproval?
    var pendingExitPlanModeFollowUp: PendingExitPlanModeFollowUp?
    var pendingExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance?
    @ObservationIgnored var pendingExitPlanModeFollowUpQuietTask: Task<Void, Never>?
    var runtimePermissionMode: String?
    var runtimePlanModeEnabled: Bool?
    var runtimeSpeedMode: AgentSpeedMode?
    var lastNonPlanPermissionMode: String?
    var liveSessionConfig: AgentSpawnConfig?
    var pendingSessionSettingsChange: PendingSessionSettingsChange?
    var retryableFailedMessageIDs: Set<String> = []
    var retryableFailedMessageStagedContexts: [String: String] = [:]
    var retryableFailedMessageTransportTexts: [String: String] = [:]
    var retryableFailedMessageAttachments: [String: [LocalImageAttachment]] = [:]
    var retryableFailedMessageFileAttachments: [String: [LocalFileAttachment]] = [:]
    var retryableFailedMessageAppShots: [String: [AppShotAttachment]] = [:]
    var retryableFailedMessageProviderMetadata: [String: [String: AgentCLIKit.JSONValue]] = [:]
    var transcriptImageAttachments: [String: [LocalImageAttachment]] = [:]
    var transcriptFileAttachments: [String: [LocalFileAttachment]] = [:]
    var transcriptAppShots: [String: [AppShotAttachment]] = [:]
    var appShotProviderSessionTitleFallback: String?
    var pendingSyntheticAssistantDuplicateText: String?
    var isGoalModeArmed = false
    var goalSnapshot: AgentGoalSnapshot? {
        didSet {
            guard isExistingGoalControllerTurnActive else {
                return
            }
            if goalSnapshot?.status.isTerminal == true {
                finishExistingSessionGoalControllerTurn(interrupted: false)
            } else if goalSnapshot == nil {
                finishExistingSessionGoalControllerTurn(interrupted: true)
            }
        }
    }
    var isExistingGoalControllerTurnActive = false
    var dismissedTerminalGoalKeys: Set<String> = []
    var lastPersistedGoalRecordKey: String?
    var goalActionError: String?

    var hasActiveSessionHandoff: Bool {
        isAwaitingHandoffSteering
            || isHandingOffSession
            || pendingHandoffOutput != nil
            || handoffCountdownRemaining != nil
            || failedSessionHandoffMessage != nil
    }

    var isNormalSteeringBlockedBySessionHandoff: Bool {
        hasActiveSessionHandoff || (isSessionHandoffSeedTurnActive && turnState.isActive)
    }

    var shouldShowInterruptedCue: Bool {
        lastTurnInterrupted
    }

    var isAwaitingExitPlanModeFollowUp: Bool {
        pendingExitPlanModeFollowUp?.phase == .awaitingDeniedExitTurn
    }

    var isViewMounted: Bool {
        mountedViewCount > 0
    }

    func registerViewMount() {
        mountedViewCount += 1
    }

    func unregisterViewMount() {
        mountedViewCount = max(mountedViewCount - 1, 0)
    }

    func stageAppShot(_ appShot: AppShotAttachment) {
        stagedAppShots.append(appShot)
        inputDraftIsEffectivelyEmpty = false
    }

    func removeStagedAppShot(id: String) {
        stagedAppShots.removeAll { $0.id == id }
        refreshInputDraftEffectiveEmptyForAttachments()
    }

    func refreshInputDraftEffectiveEmptyForAttachments() {
        let textIsEffectivelyEmpty = ComposerDraft(
            text: inputDraft,
            source: inputDraftSource
        ).textIsEffectivelyEmpty
        inputDraftIsEffectivelyEmpty = textIsEffectivelyEmpty &&
            stagedImageAttachments.isEmpty &&
            stagedFileAttachments.isEmpty &&
            stagedAppShots.isEmpty
    }

    func appendStreamingChunk(_ text: String) {
        completeThoughtText()
        if streamingTextIsSnapshot {
            streamingText = nil
            streamingTextIsSnapshot = false
        }
        if streamingText == nil {
            streamingText = text
        } else {
            streamingText?.append(text)
        }
    }

    func replaceStreamingText(_ text: String) {
        completeThoughtText()
        streamingText = text
        streamingTextIsSnapshot = true
    }

    func appendThoughtChunk(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        if thoughtText == nil {
            completedThoughtText = nil
            thoughtSequence += 1
            thoughtText = text
        } else {
            thoughtText?.append(text)
        }
    }

    func completeThoughtText() {
        guard let thoughtText, !thoughtText.isEmpty else {
            return
        }
        completedThoughtText = thoughtText
        completedThoughtSequence = thoughtSequence
        self.thoughtText = nil
    }

    func clearThoughtText() {
        thoughtText = nil
        completedThoughtText = nil
    }

    func clearThoughtText(ifNeeded shouldClear: Bool) {
        guard shouldClear else {
            return
        }
        clearThoughtText()
    }

    func clearAssistantStreamingText() {
        streamingText = nil
        streamingTextIsSnapshot = false
    }

    func clearStreamingText() {
        clearAssistantStreamingText()
        clearThoughtText()
    }

    func endTurn() {
        if turnState.isActive || (hasDeferredControllerTerminalBoundary && lastTurnInterrupted) {
            recordControllerTerminalBoundary()
            hasDeferredControllerTerminalBoundary = false
        }
        // The fresh-session handoff seed blocks normal steering only until any terminal turn boundary.
        turnState.endTurn()
        isSessionHandoffSeedTurnActive = false
    }

    func deferControllerTerminalBoundary() {
        hasDeferredControllerTerminalBoundary = true
        endTurnWithoutTerminalBoundary()
    }

    func completeDeferredControllerTurn() {
        guard hasDeferredControllerTerminalBoundary else {
            endTurn()
            return
        }
        recordControllerTerminalBoundary()
        hasDeferredControllerTerminalBoundary = false
        endTurnWithoutTerminalBoundary()
    }

    func rollBackOptimisticTurn() {
        endTurnWithoutTerminalBoundary()
    }

    func endTurnWithoutTerminalBoundary() {
        turnState.endTurn()
        isSessionHandoffSeedTurnActive = false
    }

    func beginExistingSessionGoalControllerTurn() {
        isExistingGoalControllerTurnActive = true
        if goalSnapshot?.status.isTerminal == true {
            finishExistingSessionGoalControllerTurn(interrupted: false)
        }
    }

    private func finishExistingSessionGoalControllerTurn(interrupted: Bool) {
        isExistingGoalControllerTurnActive = false
        if interrupted {
            lastTurnInterrupted = true
        }
        endTurn()
    }

    private func recordControllerTerminalBoundary() {
        let result: ConversationTerminalBoundary.Result
        if lastTurnInterrupted {
            result = .interrupted
        } else if let controllerTerminalFailureMessage {
            result = .failed(message: controllerTerminalFailureMessage)
        } else {
            result = .succeeded
        }
        lastControllerTerminalBoundary = ConversationTerminalBoundary(
            sequence: (lastControllerTerminalBoundary?.sequence ?? 0) &+ 1,
            wasVisible: currentTurnActivityVisibility == .visible,
            result: result
        )
    }

    func markRetryableFailedMessage(
        id: String,
        stagedContext: String?,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
        fileAttachments: [LocalFileAttachment] = [],
        appShots: [AppShotAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:]
    ) {
        retryableFailedMessageIDs.insert(id)
        if let stagedContext {
            retryableFailedMessageStagedContexts[id] = stagedContext
        } else {
            retryableFailedMessageStagedContexts.removeValue(forKey: id)
        }
        if let transportText {
            retryableFailedMessageTransportTexts[id] = transportText
        } else {
            retryableFailedMessageTransportTexts.removeValue(forKey: id)
        }
        if attachments.isEmpty {
            retryableFailedMessageAttachments.removeValue(forKey: id)
        } else {
            retryableFailedMessageAttachments[id] = attachments
        }
        if fileAttachments.isEmpty {
            retryableFailedMessageFileAttachments.removeValue(forKey: id)
        } else {
            retryableFailedMessageFileAttachments[id] = fileAttachments
        }
        if appShots.isEmpty {
            retryableFailedMessageAppShots.removeValue(forKey: id)
        } else {
            retryableFailedMessageAppShots[id] = appShots
        }
        if providerMetadata.isEmpty {
            retryableFailedMessageProviderMetadata.removeValue(forKey: id)
        } else {
            retryableFailedMessageProviderMetadata[id] = providerMetadata
        }
    }

    func clearRetryableFailedMessage(id: String) {
        retryableFailedMessageIDs.remove(id)
        retryableFailedMessageStagedContexts.removeValue(forKey: id)
        retryableFailedMessageTransportTexts.removeValue(forKey: id)
        retryableFailedMessageAttachments.removeValue(forKey: id)
        retryableFailedMessageFileAttachments.removeValue(forKey: id)
        retryableFailedMessageAppShots.removeValue(forKey: id)
        retryableFailedMessageProviderMetadata.removeValue(forKey: id)
    }

    func markTranscriptImageAttachments(id: String, attachments: [LocalImageAttachment]) {
        if attachments.isEmpty {
            transcriptImageAttachments.removeValue(forKey: id)
        } else {
            transcriptImageAttachments[id] = attachments
        }
    }

    func markTranscriptFileAttachments(id: String, attachments: [LocalFileAttachment]) {
        if attachments.isEmpty {
            transcriptFileAttachments.removeValue(forKey: id)
        } else {
            transcriptFileAttachments[id] = attachments
        }
    }

    func markTranscriptAppShots(id: String, appShots: [AppShotAttachment]) {
        if appShots.isEmpty {
            transcriptAppShots.removeValue(forKey: id)
        } else {
            transcriptAppShots[id] = appShots
        }
    }

    func visibleGoalSnapshot() -> AgentGoalSnapshot? {
        guard let goalSnapshot else {
            return nil
        }
        if goalSnapshot.status.isTerminal,
           dismissedTerminalGoalKeys.contains(goalSnapshot.stableGoalKey) {
            return nil
        }
        return goalSnapshot
    }
}
