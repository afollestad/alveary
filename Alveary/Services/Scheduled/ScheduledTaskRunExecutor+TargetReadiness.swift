import Foundation
import SwiftData

extension DefaultScheduledTaskRunExecutor {
    /// Retain the lease until provider-history recovery settles, then validate fresh models before any run mutation.
    func activateLeaseIfTargetIsReady(
        _ lease: ConversationControllerLease,
        resolveRun: () throws -> ScheduledTaskRun
    ) async throws {
        do {
            try Task.checkCancellation()
            lease.activate()
            while let recovery = lease.viewModel.toolApprovalRestoreTask {
                await recovery.value
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            let run = try resolveRun()
            // An existing target is also present on reused-thread runs after their first occurrence.
            guard run.targetThread == nil || lease.viewModel.isReadyForExistingScheduledTask else {
                throw ScheduledTaskRunExecutionError.existingTargetBusy
            }
        } catch {
            lease.release()
            throw error
        }
    }

    func resolveExecutionModels(
        _ materialization: ScheduledTaskRunMaterialization
    ) throws -> (ScheduledTaskRun, Conversation) {
        guard let run = modelContext.resolveScheduledTaskRun(id: materialization.runID) else {
            throw ScheduledTaskRunExecutionError.runMissing
        }
        guard run.status == .preparing else {
            throw ScheduledTaskRunExecutionError.invalidRunStatus(run.status)
        }
        guard let conversation = modelContext.resolveConversation(conversationID: materialization.conversationID) else {
            throw ScheduledTaskRunExecutionError.conversationMissing
        }
        guard let destination = run.decodedDestinationSnapshot else {
            throw ScheduledTaskRunExecutionError.conversationDoesNotBelongToRun
        }
        guard conversationBelongsToRun(run, conversation: conversation, destination: destination) else {
            throw ScheduledTaskRunExecutionError.conversationDoesNotBelongToRun
        }
        return (run, conversation)
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
