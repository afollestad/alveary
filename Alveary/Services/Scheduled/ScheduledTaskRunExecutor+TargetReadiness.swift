import Foundation

extension DefaultScheduledTaskRunExecutor {
    func activateLeaseIfTargetIsReady(
        _ lease: ConversationControllerLease,
        for run: ScheduledTaskRun
    ) throws {
        lease.activate()
        // The hazard is posting into a pre-existing thread, which the relationship states
        // directly — an `.existingThread` run always has one, a `.reusedThread` run only
        // from its second run on, and a run that created its own thread cannot be busy.
        guard run.targetThread == nil ||
            lease.viewModel.isReadyForExistingScheduledTask else {
            lease.release()
            throw ScheduledTaskRunExecutionError.existingTargetBusy
        }
    }

    /// Whether the materialized conversation is the one this run may execute in: a run that
    /// posts into a pre-existing thread must match the claimed target identity, and a run that
    /// created its own thread must own it. A reuse run without a target created its own thread —
    /// first run or the materialization self-heal.
    func conversationBelongsToRun(
        _ run: ScheduledTaskRun,
        conversation: Conversation,
        destination: ScheduledTaskDestination
    ) -> Bool {
        let postsIntoTarget: Bool
        switch destination {
        case .newThreadPerRun:
            postsIntoTarget = false
        case .existingThread:
            postsIntoTarget = true
        case .reusedThread:
            postsIntoTarget = run.targetThread != nil
        }
        if postsIntoTarget {
            return run.targetThread?.persistentModelID == conversation.thread?.persistentModelID &&
                run.targetConversationIDSnapshot == conversation.id
        }
        return conversation.thread?.scheduledTaskRun?.persistentModelID == run.persistentModelID
    }
}
