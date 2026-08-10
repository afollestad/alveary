import Foundation

extension ConversationViewModel {
    func resetSubscriptionTrackingForNewSession() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        state.activeSubscriptionToken = nil
        state.activeRuntimeActivityTurnId = nil
        state.grouper.resetInFlightStateForNewSession()
    }
}
