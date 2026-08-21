import Foundation

extension SidebarView {
    func requestArchive(_ thread: AgentThread) {
        do {
            try viewModel.requireThreadLifecycleIsUnblocked(thread)
            pendingArchiveThread = SidebarPendingThreadCleanup(thread: thread)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func requestDelete(_ thread: AgentThread) {
        do {
            try viewModel.requireThreadLifecycleIsUnblocked(thread)
            pendingDeleteThread = SidebarPendingThreadCleanup(thread: thread)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func archiveConfirmationMessage(title: String) -> String {
        "This archives \"\(title)\". "
            + "You can find archived threads under Archived in the sidebar."
    }

    func deleteConfirmationMessage(for pending: SidebarPendingThreadCleanup) -> String {
        threadDeleteConfirmationMessage(title: pending.title, isTask: pending.isTask)
    }
}
