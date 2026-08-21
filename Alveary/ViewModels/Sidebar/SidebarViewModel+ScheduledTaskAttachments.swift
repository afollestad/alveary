import Foundation

extension SidebarViewModel {
    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        try threadLifecycle.requireNoScheduledTaskAttachment(thread)
    }

    /// Why archiving or deleting this thread is refused, or nil when it is not. Both kinds of
    /// in-flight work read the same way to the sidebar, which disables the controls and shows this
    /// as their tooltip — so a new kind belongs here rather than as a second reason the row juggles.
    ///
    /// Only work already underway counts: a schedule merely *targeting* the thread, or a review
    /// proposal merely waiting on the user, leaves the lifecycle alone.
    func threadCleanupBlockedReason(for thread: AgentThread) -> String? {
        let error = threadLifecycle.activeScheduledTaskRunError(for: thread)
            ?? threadLifecycle.activeReviewSubmissionError(for: thread)
        return error?.localizedDescription
    }

    func requireThreadLifecycleIsUnblocked(_ thread: AgentThread) throws {
        try threadLifecycle.requireThreadLifecycleIsUnblocked(thread)
    }

    func requireThreadLifecycleIsUnblocked(in project: Project) throws {
        for thread in liveThreads(forProjectPath: project.path) {
            try requireThreadLifecycleIsUnblocked(thread)
        }
    }

    func presentSidebarError(_ error: Error) {
        switch error as? SidebarViewModelError {
        case .scheduledTaskAttachment, .activeScheduledTaskRunAttachment, .activeReviewSubmission:
            scheduledTaskAttachmentAlert = error.localizedDescription
        default:
            presentGeneralSidebarError(error)
        }
    }
}
