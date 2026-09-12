import Foundation
import Observation
import SwiftData

enum WorkspaceFolderOwner: Hashable {
    case project(String)
    case thread(PersistentIdentifier)
}

/// Owned by one window. Folder choices are transient UI state, independent of a session's working directory.
@MainActor
@Observable
final class WorkspaceFolderSelection {
    private var discoveredRepositories: [WorkspaceFolderTarget: String] = [:]
    private var repositoryRequests: [WorkspaceFolderTarget: UUID] = [:]
    private var selectedFolderIDs: [WorkspaceFolderOwner: String] = [:]
    private(set) var revision: UInt64 = 0

    func selected(in folders: [WorkspaceFolderTarget], owner: WorkspaceFolderOwner) -> WorkspaceFolderTarget? {
        folders.first { $0.id == selectedFolderIDs[owner] } ?? folders.first { $0.isPrimary } ?? folders.first
    }

    func repository(for folder: WorkspaceFolderTarget) -> String? {
        folder.repository ?? discoveredRepositories[folder]
    }

    /// Grants and private workspaces can acquire a Git remote after creation. Cache only against
    /// the captured folder, and reject older probes of the same folder after a replacement request.
    func refreshRepository(
        for folder: WorkspaceFolderTarget,
        resolve: (String) async -> String?
    ) async {
        guard folder.repository == nil else { return }
        let request = UUID()
        repositoryRequests[folder] = request
        let repository = await resolve(folder.directory)
        guard !Task.isCancelled, repositoryRequests[folder] == request else { return }
        discoveredRepositories[folder] = repository
    }

    func select(_ folder: WorkspaceFolderTarget, owner: WorkspaceFolderOwner) {
        guard selectedFolderIDs[owner] != folder.id else { return }
        selectedFolderIDs[owner] = folder.id
        revision &+= 1
    }
}

struct WorkspaceFolderContext {
    let owner: WorkspaceFolderOwner
    let folders: [WorkspaceFolderTarget]
}

extension ContentView {
    var selectedWorkspaceFolderContext: WorkspaceFolderContext? {
        switch appState.selectedSidebarItem?.resolved(in: uiModelContext) {
        case .project(let project):
            WorkspaceFolderContext(owner: .project(project.id), folders: project.workspaceFolderTargets)
        case .thread(let thread) where thread.archivedAt == nil:
            WorkspaceFolderContext(owner: .thread(thread.persistentModelID), folders: thread.workspaceFolderTargets)
        default:
            nil
        }
    }

    var selectedWorkspaceFolder: WorkspaceFolderTarget? {
        guard let context = selectedWorkspaceFolderContext else { return nil }
        return folderSelection.selected(in: context.folders, owner: context.owner)
    }

    var selectedProjectWorkspaceFolder: WorkspaceFolderTarget? {
        guard let context = selectedWorkspaceFolderContext, case .project = context.owner else { return nil }
        return folderSelection.selected(in: context.folders, owner: context.owner)
    }
}
