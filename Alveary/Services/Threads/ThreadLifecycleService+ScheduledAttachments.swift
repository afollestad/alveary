import Foundation
import SwiftData

/// Coordinates per-run teardown before lifecycle mutations. Exact callbacks stop and pause;
/// legacy attachments retain their existing in-flight refusal and detachment behavior.
extension ThreadLifecycleService {
    /// Workspace changes cannot silently unmoor a live schedule; placement changes remain allowed.
    func scheduledTaskAttachmentError(for thread: AgentThread) -> SidebarViewModelError? {
        if let definition = thread.blockingScheduledTaskAttachment {
            return .scheduledTaskAttachment(definition.title)
        }
        return activeScheduledTaskRunError(for: thread)
    }

    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        if let error = scheduledTaskAttachmentError(for: thread) {
            throw error
        }
    }

    /// Legacy in-flight targets refuse removal; exact callbacks use coordinator quiescence instead.
    func activeScheduledTaskRunError(for thread: AgentThread) -> SidebarViewModelError? {
        thread.targetedScheduledTaskRuns.contains {
            $0.isExactTargetSnapshot != true && (!$0.hasKnownTerminalStatus || $0.requiresFinalizationRecovery)
        } ? .activeScheduledTaskRunAttachment : nil
    }

    func requireNoActiveScheduledTaskRun(_ thread: AgentThread) throws {
        if let error = activeScheduledTaskRunError(for: thread) {
            throw error
        }
    }

    /// Why publishing a review forbids archiving or deleting the thread it is publishing from.
    ///
    /// The same shape as `activeScheduledTaskRunError`, and for the same reason: a proposal merely
    /// waiting on the user never blocks the lifecycle — dismissing the card is how that ends — but a
    /// submit already talking to GitHub would be abandoned mid-flight, with the review half written
    /// and no card left to retry from.
    func activeReviewSubmissionError(for thread: AgentThread) -> SidebarViewModelError? {
        // Ahead of `thread.conversations`, not after it: see `isIdle`.
        guard !reviewSubmissionActivity.isIdle else {
            return nil
        }
        return reviewSubmissionActivity.isSubmitting(anyOf: thread.conversations.map(\.id))
            ? .activeReviewSubmission
            : nil
    }

    func requireNoActiveReviewSubmission(_ thread: AgentThread) throws {
        if let error = activeReviewSubmissionError(for: thread) {
            throw error
        }
    }

    /// Both lifecycle refusals in one call, so a guard site cannot pick up one and forget the other.
    func requireThreadLifecycleIsUnblocked(_ thread: AgentThread) throws {
        try requireNoActiveScheduledTaskRun(thread)
        try requireNoActiveReviewSubmission(thread)
    }

    /// Recheck exact callbacks after suspension without repeating the original run's completed barrier.
    func quiesceScheduledTaskRunIfNeeded(threadID: PersistentIdentifier) async throws {
        guard let thread = modelContext.resolveThread(id: threadID) else { return }
        _ = try await quiesceScheduledTaskRunIfNeeded(for: thread, includeOwnedRun: false)
    }

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread, includeOwnedRun: Bool = true) async throws -> AgentThread {
        let threadID = thread.persistentModelID
        let runIDs = thread.targetedScheduledTaskRuns.filter { $0.isExactTargetSnapshot == true }.map(\.persistentModelID)
            + [includeOwnedRun ? thread.scheduledTaskRun?.persistentModelID : nil].compactMap { $0 }
        for runID in runIDs { try await stopAndWaitForScheduledTaskRun(runID) }
        guard let currentThread = modelContext.resolveThread(id: threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        try requireScheduledRunsQuiescent(currentThread)
        if currentThread.scheduledTaskRun?.hasKnownTerminalStatus == false {
            throw SidebarViewModelError.scheduledTaskRunStillActive
        }
        return currentThread
    }

    /// Recheck after every suspension and immediately before removing model rows.
    func requireScheduledRunsQuiescent(_ thread: AgentThread) throws {
        guard !thread.hasBlockingScheduledTaskRunAttachment else {
            throw SidebarViewModelError.scheduledTaskRunStillActive
        }
    }

    func quiesceExactCallbacks(conversationID: String) async throws {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID), let thread = conversation.thread else { return }
        let ids = thread.targetedScheduledTaskRuns.filter {
            $0.isExactTargetSnapshot == true && $0.targetConversationIDSnapshot == conversationID
        }.map(\.persistentModelID)
        for id in ids { try await stopAndWaitForScheduledTaskRun(id) }
        guard let live = modelContext.resolveConversation(conversationID: conversationID) else { return }
        guard live.thread?.targetedScheduledTaskRuns.contains(where: {
            $0.targetConversationIDSnapshot == conversationID && (!$0.hasKnownTerminalStatus || $0.requiresFinalizationRecovery)
        }) != true else { throw SidebarViewModelError.scheduledTaskRunStillActive }
    }

    /// Publishes the definitions a lifecycle commit changed. Called only after that commit's
    /// save succeeds, so a rolled-back archive never announces a schedule change.
    func postScheduledTasksDetached(definitionIDs: [String]) {
        NotificationCenter.default.postScheduledTasksDetached(definitionIDs: definitionIDs)
    }
}
