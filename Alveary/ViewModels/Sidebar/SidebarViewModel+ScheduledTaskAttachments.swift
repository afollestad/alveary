import Foundation

extension SidebarViewModel {
    func scheduledTaskAttachmentReason(for thread: AgentThread) -> String? {
        scheduledTaskAttachmentError(for: thread)?.localizedDescription
    }

    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        try threadLifecycle.requireNoScheduledTaskAttachment(thread)
    }

    func requireNoScheduledTaskAttachments(in project: Project) throws {
        for thread in liveThreads(forProjectPath: project.path) {
            try requireNoScheduledTaskAttachment(thread)
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

    private func scheduledTaskAttachmentError(for thread: AgentThread) -> SidebarViewModelError? {
        threadLifecycle.scheduledTaskAttachmentError(for: thread)
    }
}
