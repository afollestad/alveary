import Foundation

extension SidebarViewModel {
    var defaultThreadCleanupAction: ThreadCleanupAction {
        settingsService.current.defaultThreadCleanupAction
    }

    var pendingDraftProjectPath: String? {
        pendingDraftProjectPaths[.project]
    }

    func directoryExists(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    func threadStatus(for thread: AgentThread) -> ThreadStatus {
        if activeForkSourceThreadIDs.contains(thread.persistentModelID), thread.archivedAt == nil {
            return .busy
        }
        return thread.displayStatus { agentsManager.status(for: $0.id) }
    }

}
