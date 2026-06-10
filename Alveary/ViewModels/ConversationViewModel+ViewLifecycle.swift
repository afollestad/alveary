import Foundation

extension ConversationViewModel {
    func activateViewLifecycle() {
        guard !hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = true
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
        subscriptionTask?.cancel()
        subscriptionTask = nil
        queueDrainTask?.cancel()
        queueDrainTask = nil
        cancelPendingExitPlanModeFollowUpQuietTaskForViewDeactivation()
    }
}
