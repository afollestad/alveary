import Foundation

@testable import Alveary

func makeSidebarTaskWorkspaceService() -> DefaultTaskWorkspaceOwnershipService {
    DefaultTaskWorkspaceOwnershipService(
        privateWorkspacesRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-sidebar-private-\(UUID().uuidString)", isDirectory: true),
        worktreeOwnershipRecordsRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-sidebar-worktrees-\(UUID().uuidString)", isDirectory: true)
    )
}
