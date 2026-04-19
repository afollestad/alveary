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
    var lastObservedEventIndex = 0
    var lastPersistedEventIndex = 0
    var activeBufferGeneration: UUID?
    var activeSubscriptionToken: UUID?
    var inputDraft = ""
    var grouper = ChatItemGrouper()
    var respawnAttempts = 0
    var showPermissionBanner = false
    var lastPermissionDeniedToolNames: Set<String> = []
    var inFlightQueuedMessageID: UUID?
    var setupPhase: SetupPhase?
    var retryableFailedMessageIDs: Set<String> = []
    var retryableFailedMessageStagedContexts: [String: String] = [:]

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
