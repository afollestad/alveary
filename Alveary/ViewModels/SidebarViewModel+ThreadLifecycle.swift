import SwiftData

extension SidebarViewModel {
    func postThreadLifecycleChanged(threadID: PersistentIdentifier, mode: AgentThreadMode) {
        threadLifecycle.postThreadLifecycleChanged(threadID: threadID, mode: mode)
    }

    /// The archived row behind a `.threadLifecycleChanged` notification, or `nil` when the thread
    /// is still active or gone. Restores post the same notification, so callers reacting to an
    /// archive have to check.
    func archivedThread(id: PersistentIdentifier) -> AgentThread? {
        guard let thread = modelContext.resolveThread(id: id),
              thread.archivedAt != nil else {
            return nil
        }
        return thread
    }
}
