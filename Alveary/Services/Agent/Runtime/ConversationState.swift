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
    let message: String
    let sourceTurnId: String?
    let sourceSubscriptionToken: UUID?
    let sourceBufferGeneration: UUID?
    let sourceEventIndex: Int
    var lastObservedEventIndex: Int
    var phase: Phase
}

@MainActor
@Observable
final class ConversationState {
    let messageQueue = MessageQueue()
    let turnState = TurnState()

    var streamingText: String?
    var lastTurnError: String?
    var lastTurnInterrupted = false
    var stagedContext: String?
    var sessionContinuityNotice: String?
    var isSendingMessage = false
    var isCancellingTurn = false
    var isCancellingInitialSetup = false
    var isReconfiguringSession = false
    var isHandingOffSession = false
    var lastObservedEventIndex = 0
    var lastPersistedEventIndex = 0
    var activeBufferGeneration: UUID?
    var activeSubscriptionToken: UUID?
    var activeRuntimeActivityTurnId: String?
    var currentTurnActivityVisibility: AgentTurnActivityVisibility = .hidden
    var hasRecordedLocalTurnEndActivity = false
    var inputDraft = ""
    var inputDraftSource: ComposerDraftSource = .legacyText
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
    var isAutomaticSessionHandoffPending = false
    var hiddenHandoffResponse = ""
    var pendingHandoffOutput: String?
    var failedSessionHandoffMessage: String?
    var handoffCountdownRemaining: Int?
    var handoffDraftBaseline: String?
    var sessionHandoffCountdownTask: Task<Void, Never>?
    var grouper = ChatItemGrouper()
    var respawnAttempts = 0
    var inFlightQueuedMessageID: UUID?
    var setupPhase: SetupPhase?
    var pendingToolApproval: PendingToolApproval?
    var pendingExitPlanModeFollowUp: PendingExitPlanModeFollowUp?
    @ObservationIgnored var pendingExitPlanModeFollowUpQuietTask: Task<Void, Never>?
    var runtimePermissionMode: String?
    var runtimePlanModeEnabled: Bool?
    var runtimeSpeedMode: AgentSpeedMode?
    var lastNonPlanPermissionMode: String?
    var liveSessionConfig: AgentSpawnConfig?
    var pendingSessionSettingsChange: PendingSessionSettingsChange?
    var retryableFailedMessageIDs: Set<String> = []
    var retryableFailedMessageStagedContexts: [String: String] = [:]
    var pendingSyntheticAssistantDuplicateText: String?

    var hasActiveSessionHandoff: Bool {
        isAwaitingHandoffSteering
            || isHandingOffSession
            || pendingHandoffOutput != nil
            || handoffCountdownRemaining != nil
            || failedSessionHandoffMessage != nil
    }

    var shouldShowInterruptedCue: Bool {
        lastTurnInterrupted
    }

    var isAwaitingExitPlanModeFollowUp: Bool {
        pendingExitPlanModeFollowUp?.phase == .awaitingDeniedExitTurn
    }

    func appendStreamingChunk(_ text: String) {
        if streamingText == nil {
            streamingText = text
        } else {
            streamingText?.append(text)
        }
    }

    func clearStreamingText() {
        streamingText = nil
    }

    func markRetryableFailedMessage(id: String, stagedContext: String?) {
        retryableFailedMessageIDs.insert(id)
        if let stagedContext {
            retryableFailedMessageStagedContexts[id] = stagedContext
        } else {
            retryableFailedMessageStagedContexts.removeValue(forKey: id)
        }
    }

    func clearRetryableFailedMessage(id: String) {
        retryableFailedMessageIDs.remove(id)
        retryableFailedMessageStagedContexts.removeValue(forKey: id)
    }
}
