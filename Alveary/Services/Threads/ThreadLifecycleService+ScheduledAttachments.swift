import Foundation
import SwiftData

/// What a scheduled task still forbids on the thread it posts into, and how a lifecycle mutation
/// quiesces a run before committing.
///
/// A schedule deliberately does **not** own its target's sidebar placement or existence: unpin,
/// section moves, archive, and delete all proceed, and `ScheduledTaskTargetDetachment` converts
/// the definition to its self-healing reuse mode when the thread goes away. What survives here
/// are the narrower refusals — work already in flight, and mutations that would silently
/// retarget a live definition.
extension ThreadLifecycleService {
    /// Why a schedule forbids a mutation that would change what its target *is*.
    ///
    /// Deliberately not the archive, delete, unpin, or section-move guard: those are user actions
    /// a schedule must survive rather than refuse, and `ScheduledTaskTargetDetachment` converts
    /// the definition instead. Two callers remain, both of which would silently retarget or
    /// unmoor a live schedule: the Task-to-Project drop, which swaps the workspace a run derives
    /// from the thread, and deleting the main conversation a definition names.
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

    /// Why an in-flight run forbids archiving or deleting the thread it is posting into.
    ///
    /// The run half of `scheduledTaskAttachmentError(for:)`, split out because a *definition*
    /// pointing at this thread no longer blocks its lifecycle — only work already underway does.
    func activeScheduledTaskRunError(for thread: AgentThread) -> SidebarViewModelError? {
        thread.hasBlockingScheduledTaskRunAttachment ? .activeScheduledTaskRunAttachment : nil
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

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread) async throws -> AgentThread {
        let threadID = thread.persistentModelID
        guard let run = thread.scheduledTaskRun else {
            return thread
        }
        let runID = run.persistentModelID

        try await stopAndWaitForScheduledTaskRun(runID)

        guard let currentThread = modelContext.resolveThread(id: threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        if let currentRun = currentThread.scheduledTaskRun,
           !currentRun.hasKnownTerminalStatus {
            throw SidebarViewModelError.scheduledTaskRunStillActive
        }
        return currentThread
    }

    /// Publishes the definitions a lifecycle commit converted. Called only after that commit's
    /// save succeeds, so a rolled-back archive never announces a schedule change.
    func postScheduledTasksDetached(definitionIDs: [String]) {
        NotificationCenter.default.postScheduledTasksDetached(definitionIDs: definitionIDs)
    }
}
