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
    var retryableFailedMessageAppShots: [String: [AppShotAttachment]] = [:]
    var retryableFailedMessageProviderMetadata: [String: [String: AgentCLIKit.JSONValue]] = [:]
    var transcriptImageAttachments: [String: [LocalImageAttachment]] = [:]
    var transcriptAppShots: [String: [AppShotAttachment]] = [:]
    var appShotProviderSessionTitleFallback: String?
    var pendingSyntheticAssistantDuplicateText: String?
    var isGoalModeArmed = false
    var goalSnapshot: AgentGoalSnapshot?
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
        // The fresh-session handoff seed blocks normal steering only until any terminal turn boundary.
        turnState.endTurn()
        isSessionHandoffSeedTurnActive = false
    }

    func markRetryableFailedMessage(
        id: String,
        stagedContext: String?,
        transportText: String? = nil,
        attachments: [LocalImageAttachment] = [],
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
