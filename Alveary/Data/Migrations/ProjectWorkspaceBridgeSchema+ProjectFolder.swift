import Foundation
import SwiftData

/// Frozen membership shape shared by the bridge and the first folder-aware schema.
extension ProjectWorkspaceBridgeSchema {
    @Model
    final class ProjectFolder {
        @Attribute(.unique) var id: String
        var path: String
        var sortOrder: Int
        var gitRemote: String?
        var remoteName: String?
        var gitBranch: String?
        var baseRef: String?
        var githubRepository: String?
        var githubConnected: Bool
        var project: Project?

        init() {
            id = UUID().uuidString
            path = ""
            sortOrder = 0
            githubConnected = false
        }
    }
}
