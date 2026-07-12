import Foundation

extension ConversationViewModel {
    func activateViewLifecycle() {
        guard !hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = true
        hasEverActivatedViewLifecycle = true
        state.registerViewMount()
        activateControllerLifecycleIfNeeded()
    }

    func activateBackgroundLifecycle() {
        guard !hasActivatedBackgroundLifecycle else {
            return
        }

        hasActivatedBackgroundLifecycle = true
        activateControllerLifecycleIfNeeded()
    }

    func deactivateViewLifecycle() {
        guard hasActivatedViewLifecycle else {
            return
        }

        hasActivatedViewLifecycle = false
        state.unregisterViewMount()
        deactivateControllerLifecycleIfNeeded()
    }

    func deactivateBackgroundLifecycle() {
        guard hasActivatedBackgroundLifecycle else {
            return
        }

        hasActivatedBackgroundLifecycle = false
        deactivateControllerLifecycleIfNeeded()
    }
}

private extension ConversationViewModel {
    func activateControllerLifecycleIfNeeded() {
        guard subscriptionTask == nil else {
            scheduleQueueDrainIfNeeded()
            return
        }

        hydratePendingRestoreContextIfNeeded()
        hydratePendingToolApprovalIfNeeded()
        subscribe()
        schedulePendingExitPlanModeFollowUpQuietFallbackIfNeeded()
        scheduleQueueDrainIfNeeded()
    }

    func deactivateControllerLifecycleIfNeeded() {
        guard !hasActivatedControllerLifecycle else {
            return
        }

        subscriptionTask?.cancel()
        subscriptionTask = nil
        queueDrainTask?.cancel()
        queueDrainTask = nil
        cancelPendingExitPlanModeFollowUpQuietTaskForViewDeactivation()
    }
}
