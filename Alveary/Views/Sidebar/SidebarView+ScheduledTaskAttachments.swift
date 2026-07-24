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
        "This archives \"\(thread.displayName())\". "
            + "You can find archived threads under Archived in the sidebar."
    }

    func deleteConfirmationMessage(for thread: AgentThread) -> String {
        threadDeleteConfirmationMessage(for: thread)
    }
}
