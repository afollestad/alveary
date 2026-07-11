import Foundation

extension ConversationViewModel {
    func activateViewLifecycle() {
        guard !hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = true
        hasEverActivatedViewLifecycle = true
        state.registerViewMount()
        hydratePendingRestoreContextIfNeeded()
        hydratePendingToolApprovalIfNeeded()
        subscribe()
        schedulePendingExitPlanModeFollowUpQuietFallbackIfNeeded()
        scheduleQueueDrainIfNeeded()
    }

    func deactivateViewLifecycle() {
        guard hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = false
        state.unregisterViewMount()
        subscriptionTask?.cancel()
        subscriptionTask = nil
        queueDrainTask?.cancel()
        queueDrainTask = nil
        cancelPendingExitPlanModeFollowUpQuietTaskForViewDeactivation()
    }
}
