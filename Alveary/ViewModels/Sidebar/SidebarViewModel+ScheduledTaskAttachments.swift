import Foundation

extension SidebarViewModel {
    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        try threadLifecycle.requireNoScheduledTaskAttachment(thread)
    }

    /// The shared lifecycle refusal also supplies the disabled controls' tooltip.
    ///
    /// Only work already underway counts: a schedule merely *targeting* the thread, or a review
    /// proposal merely waiting on the user, leaves the lifecycle alone.
    func threadCleanupBlockedReason(for thread: AgentThread) -> String? {
        threadLifecycle.threadCleanupError(for: thread)?.localizedDescription
    }

    func requireThreadLifecycleIsUnblocked(_ thread: AgentThread) throws {
        try threadLifecycle.requireThreadLifecycleIsUnblocked(thread)
    }

    func requireThreadLifecycleIsUnblocked(in project: Project) throws {
        for thread in liveThreads(forProjectID: project.id) {
            try requireThreadLifecycleIsUnblocked(thread)
        }
    }

    func presentSidebarError(_ error: Error) {
        switch error as? SidebarViewModelError {
        case .scheduledTaskAttachment, .activeScheduledTaskRunAttachment, .activeReviewSubmission, .activeReview:
            scheduledTaskAttachmentAlert = error.localizedDescription
        default:
            presentGeneralSidebarError(error)
        }
    }
}
