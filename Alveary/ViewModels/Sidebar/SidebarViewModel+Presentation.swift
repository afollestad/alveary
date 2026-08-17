import Foundation
import SwiftData

extension SidebarViewModel {
    var defaultThreadCleanupAction: ThreadCleanupAction {
        settingsService.current.defaultThreadCleanupAction
    }

    var pendingDraftProjectPath: String? {
        pendingDraftProjectPaths[.project]
    }

    /// `nonisolated` so the off-main cleanup path (`cleanupThread` and the owned-worktree helpers
    /// in `SidebarViewModel+TaskWorkspaceCleanup.swift`) can stat without hopping back to the
    /// main actor; a synchronous main-actor caller still runs it inline on its own executor.
    nonisolated func directoryExists(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    /// Value-typed by contract: callers snapshot `conversationStatuses` while the rows are live
    /// (the sidebar's render pass, `ThreadDetailView.body`), so this can run from any later
    /// render without touching a model that a delete may have removed.
    func threadStatus(
        threadID: PersistentIdentifier,
        isArchived: Bool,
        conversationStatuses: [ConversationStatusSnapshot]
    ) -> ThreadStatus {
        if activeForkSourceThreadIDs.contains(threadID), !isArchived {
            return .busy
        }
        return .folded(
            isArchived: isArchived,
            conversations: conversationStatuses,
            runtimeFor: { agentsManager.status(for: $0) }
        )
    }

}
