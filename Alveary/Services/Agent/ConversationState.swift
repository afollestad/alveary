import Foundation
import Observation

@MainActor
@Observable
final class ConversationState {
    let messageQueue = MessageQueue()
    let turnState = TurnState()

    var streamingText: String?
    var lastTurnError: String?
    var stagedContext: String?
    var sessionContinuityNotice: String?
    var isSendingMessage = false
    var isReconfiguringSession = false
    var lastObservedEventIndex = 0
    var lastPersistedEventIndex = 0
    var activeBufferGeneration: UUID?
    var activeSubscriptionToken: UUID?
    var inputDraft = ""
    var selectedModel: String?
    var grouper = ChatItemGrouper()
    var respawnAttempts = 0
    var showPermissionBanner = false
    var lastPermissionDeniedToolNames: Set<String> = []
    var inFlightQueuedMessageID: UUID?
    var setupPhase: SetupPhase?

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
}
