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
    case project(String)

    init(selection: SidebarItem?) {
        switch selection {
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .project(let project):
            self = .project(project.path)
        case .skills, .mcp, .scheduled, .pullRequests, .archived, .settings, nil:
            self = .none
        }
    }

    var isProjectActionCapable: Bool {
        self != .none
    }

    /// Only a selected project row puts the settings editor on screen, so only that
    /// selection's own config write refreshes the toolbar in place. A thread
    /// selection's actions refresh when the selection itself changes.
    func matchesChangedProjectConfig(atPath path: String) -> Bool {
        self == .project(path)
    }
}

/// What a rendered action button runs against.
///
/// A thread owner runs in the thread's worktree; a project owner — a selected
/// project row, or a draft thread that has no worktree yet — runs at the project root.
enum ToolbarProjectActionsOwner: Equatable {
    case thread(PersistentIdentifier)
    case project(String)
}

/// Resolves a selection key to the project whose actions load, plus the owner the
/// loaded buttons run against.
@MainActor
enum ToolbarProjectActionsTargetResolver {
    struct Target: Equatable {
        let projectPath: String
        let owner: ToolbarProjectActionsOwner
    }

    static func resolve(key: ToolbarProjectActionsSelection, modelContext: ModelContext) -> Target? {
        switch key {
        case .none:
            return nil
        case .project(let path):
            // A project row names its own path, so this branch reads no SwiftData.
            return Target(projectPath: path, owner: .project(path))
        case .thread(let threadID):
            guard let thread = modelContext.resolveThread(id: threadID),
                  thread.archivedAt == nil,
                  thread.effectiveMode == .project,
                  let projectPath = thread.project?.path else {
                return nil
            }

            // A draft has no worktree to run in yet, so it runs at the project root.
            let owner: ToolbarProjectActionsOwner = thread.isDraft
                ? .project(projectPath)
                : .thread(threadID)
            return Target(projectPath: projectPath, owner: owner)
        }
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

        // A project row names its own path, so an already-loaded config can render its
        // actions on this frame — an in-memory lookup, no fetch and no read. A thread
        // key cannot take this path: finding its project needs a SwiftData resolve,
        // which stays behind the yield.
        if case .project(let path) = key,
           let cached = ProjectConfigStore.shared.cached(forProjectPath: path) {
            applyToolbarProjectActions(cached.actions ?? [], owner: .project(path))
        }

        // Let the new selection paint before any SwiftData or config read starts.
        await Task.yield()

        guard toolbarProjectActionsSelection == key else {
            return
        }

        // Synchronous through the clear below, so a superseded key cannot drop a
        // newer selection's already-loaded actions.
        guard let target = ToolbarProjectActionsTargetResolver.resolve(
            key: key,
            modelContext: uiModelContext
        ) else {
            clearToolbarProjectActions()
            return
        }

        let config = await ProjectConfigStore.shared.config(forProjectPath: target.projectPath)

        guard toolbarProjectActionsSelection == key else {
            return
        }

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
              toolbarProjectActionsSelection.matchesChangedProjectConfig(atPath: path) else {
            return
        }

        Task { await refreshToolbarProjectActions() }
    }

    private func clearToolbarProjectActions() {
        toolbarProjectActions = []
        toolbarProjectActionsOwner = nil
    }
}
