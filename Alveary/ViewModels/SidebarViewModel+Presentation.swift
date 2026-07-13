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

}
