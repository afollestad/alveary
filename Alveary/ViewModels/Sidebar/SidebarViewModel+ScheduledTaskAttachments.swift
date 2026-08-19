import Foundation

extension SidebarViewModel {
    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        try threadLifecycle.requireNoScheduledTaskAttachment(thread)
    }

    /// The archive/delete reason. A definition pointing at this thread no longer blocks its
    /// lifecycle; only a run already posting into it does.
    func activeScheduledTaskRunReason(for thread: AgentThread) -> String? {
        threadLifecycle.activeScheduledTaskRunError(for: thread)?.localizedDescription
    }

    func requireNoActiveScheduledTaskRun(_ thread: AgentThread) throws {
        try threadLifecycle.requireNoActiveScheduledTaskRun(thread)
    }

    func requireNoActiveScheduledTaskRuns(in project: Project) throws {
        for thread in liveThreads(forProjectPath: project.path) {
            try requireNoActiveScheduledTaskRun(thread)
        }
    }

    func presentSidebarError(_ error: Error) {
        switch error as? SidebarViewModelError {
        case .scheduledTaskAttachment, .activeScheduledTaskRunAttachment:
            scheduledTaskAttachmentAlert = error.localizedDescription
        default:
            presentGeneralSidebarError(error)
        }
    }
}
