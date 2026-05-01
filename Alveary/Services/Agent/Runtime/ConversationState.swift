import Foundation
import Observation

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
    var inputDraft = ""
    var isAwaitingHandoffSteering = false
    var handoffSteeringCountdownRemaining: Int?
    var handoffSteeringDraftBaseline: String?
    var sessionHandoffRestorableDraft: String?
    var submittedHandoffSteeringPrompt: String?
    var sessionHandoffSteeringCountdownTask: Task<Void, Never>?
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
    var runtimePermissionMode: String?
    var lastNonPlanPermissionMode: String?
    var retryableFailedMessageIDs: Set<String> = []
    var retryableFailedMessageStagedContexts: [String: String] = [:]

    var hasActiveSessionHandoff: Bool {
        isAwaitingHandoffSteering
            || isHandingOffSession
            || pendingHandoffOutput != nil
            || handoffCountdownRemaining != nil
            || failedSessionHandoffMessage != nil
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
