import Foundation

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

    func threadStatus(
        for thread: AgentThread,
        attention: ConversationDecisionAttention
    ) -> ThreadStatus {
        if activeForkSourceThreadIDs.contains(thread.persistentModelID), thread.archivedAt == nil {
            return .busy
        }
        return thread.displayStatus(
            runtimeFor: { agentsManager.status(for: $0.id) },
            awaitsUserDecisionFor: attention.awaitsDecision
        )
    }

}
