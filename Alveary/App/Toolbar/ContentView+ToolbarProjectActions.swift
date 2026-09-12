import Foundation
import SwiftData
import SwiftUI

/// Root selection reduced to the identity the toolbar's project actions load for.
///
/// Built from selection tokens only — no SwiftData property reads — so the
/// click-to-highlight frame never waits on a fetch or a config read. Unlike
/// `DiffViewerRoutingSelection` this does not normalize `Settings` onto its
/// bookmark: the actions are click-to-run affordances for the visible selection,
/// and there is no persistent pane state to keep alive behind Settings.
enum ToolbarProjectActionsSelection: Equatable {
    case none
    case thread(PersistentIdentifier)
    case project(PersistentIdentifier)

    init(selection: SidebarItem?) {
        switch selection {
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .project(let project):
            self = .project(project.persistentModelID)
        case .skills, .mcp, .scheduled, .pullRequests, .archived, .settings, nil:
            self = .none
        }
    }

    var isProjectActionCapable: Bool {
        self != .none
    }
}

/// What a rendered action button runs against.
///
/// Capture the selected folder when actions load so a later selection cannot redirect a click.
enum ToolbarProjectActionsOwner: Equatable {
    case folder(WorkspaceFolderOwner, WorkspaceFolderTarget)
}

/// Resolves a selection key to the project whose actions load, plus the owner the
/// loaded buttons run against.
@MainActor
enum ToolbarProjectActionsTargetResolver {
    struct Target: Equatable {
        let projectPath: String
        let owner: ToolbarProjectActionsOwner
    }

    static func resolve(
        key: ToolbarProjectActionsSelection, modelContext: ModelContext,
        folderSelection: WorkspaceFolderSelection = WorkspaceFolderSelection()
    ) -> Target? {
        let owner: WorkspaceFolderOwner
        let folders: [WorkspaceFolderTarget]
        switch key {
        case .none:
            return nil
        case .project(let id):
            guard let project = modelContext.resolveProject(id: id) else { return nil }
            owner = .project(project.id)
            folders = project.workspaceFolderTargets
        case .thread(let threadID):
            guard let thread = modelContext.resolveThread(id: threadID), thread.archivedAt == nil else { return nil }
            owner = .thread(threadID)
            folders = thread.workspaceFolderTargets
        }
        guard let folder = folderSelection.selected(in: folders, owner: owner) else { return nil }
        return Target(projectPath: folder.source.path, owner: .folder(owner, folder))
    }
}

extension ContentView {
    var toolbarProjectActionsSelection: ToolbarProjectActionsSelection {
        ToolbarProjectActionsSelection(selection: appState.selectedSidebarItem)
    }

    func refreshToolbarProjectActions() async {
        let key = toolbarProjectActionsSelection

        guard key.isProjectActionCapable else {
            clearToolbarProjectActions()
            return
        }

        let revision = folderSelection.revision

        // Let the new selection paint before any SwiftData or config read starts.
        await Task.yield()

        guard !Task.isCancelled, toolbarProjectActionsSelection == key, folderSelection.revision == revision else {
            return
        }

        // Synchronous through the clear below, so a superseded key cannot drop a
        // newer selection's already-loaded actions.
        guard let target = ToolbarProjectActionsTargetResolver.resolve(
            key: key,
            modelContext: uiModelContext,
            folderSelection: folderSelection
        ) else {
            clearToolbarProjectActions()
            return
        }

        let config = await ProjectConfigStore.shared.config(forProjectPath: target.projectPath)

        guard !Task.isCancelled, toolbarProjectActionsSelection == key, folderSelection.revision == revision else {
            return
        }

        guard ToolbarProjectActionsTargetResolver.resolve(
            key: key, modelContext: uiModelContext, folderSelection: folderSelection
        ) == target else { return }
        applyToolbarProjectActions(config.actions ?? [], owner: target.owner)
    }

    /// Writing equal values would still invalidate the root body, so a cache hit that
    /// already rendered these actions must not schedule a second render pass.
    private func applyToolbarProjectActions(
        _ actions: [AlvearyProjectConfig.ProjectAction],
        owner: ToolbarProjectActionsOwner
    ) {
        if toolbarProjectActions != actions {
            toolbarProjectActions = actions
        }
        if toolbarProjectActionsOwner != owner {
            toolbarProjectActionsOwner = owner
        }
    }

    func refreshToolbarProjectActionsIfConfigChanged(_ notification: Notification) {
        guard let path = ProjectConfigChangeNotifier.changedProjectPath(in: notification),
              selectedWorkspaceFolder?.source.path == path else {
            return
        }

        Task { await refreshToolbarProjectActions() }
    }

    private func clearToolbarProjectActions() {
        toolbarProjectActions = []
        toolbarProjectActionsOwner = nil
    }
}
