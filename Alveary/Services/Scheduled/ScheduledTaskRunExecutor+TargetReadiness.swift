import Foundation

extension DefaultScheduledTaskRunExecutor {
    func activateLeaseIfTargetIsReady(
        _ lease: ConversationControllerLease,
        for run: ScheduledTaskRun
    ) throws {
        lease.activate()
        guard run.decodedDestinationSnapshot != .existingThread ||
            lease.viewModel.isReadyForExistingScheduledTask else {
            lease.release()
            throw ScheduledTaskRunExecutionError.existingTargetBusy
        }
    }
}
