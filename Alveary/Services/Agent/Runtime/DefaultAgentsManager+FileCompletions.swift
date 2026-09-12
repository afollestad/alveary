import Foundation

extension DefaultAgentsManager {
    /// Invalidate from the app-scoped runtime, including unmounted conversations. Neither the
    /// visible diff folder nor the project's current membership describes a running task's roots.
    func invalidateWorkspaceFileCompletions(roots: [String]) async {
        guard let fileListManager else { return }
        for root in Set(roots) {
            await fileListManager.invalidateCache(for: root)
        }
    }
}
