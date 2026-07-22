import Foundation

extension SidebarView {
    func requestArchive(_ thread: AgentThread) {
        do {
            try viewModel.requireNoScheduledTaskAttachment(thread)
            pendingArchiveThread = thread
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func requestDelete(_ thread: AgentThread) {
        do {
            try viewModel.requireNoScheduledTaskAttachment(thread)
            pendingDeleteThread = thread
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func archiveConfirmationMessage(for thread: AgentThread) -> String {
        if thread.effectiveMode == .task {
            return "This archives \"\(thread.displayName())\". "
                + "You can find archived tasks in Settings > Threads > Archived Tasks."
        }
        return "This archives \"\(thread.displayName())\". "
            + "You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
    }

    func deleteConfirmationMessage(for thread: AgentThread) -> String {
        threadDeleteConfirmationMessage(for: thread)
    }
}
