import Foundation

extension SidebarViewModel {
    func scheduledTaskAttachmentReason(for thread: AgentThread) -> String? {
        scheduledTaskAttachmentError(for: thread)?.localizedDescription
    }

    func requireNoScheduledTaskAttachment(_ thread: AgentThread) throws {
        if let error = scheduledTaskAttachmentError(for: thread) {
            throw error
        }
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
        if let definition = thread.blockingScheduledTaskAttachment {
            return .scheduledTaskAttachment(definition.title)
        }
        if thread.hasBlockingScheduledTaskRunAttachment {
            return .activeScheduledTaskRunAttachment
        }
        return nil
    }
}
