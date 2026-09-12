import Foundation

/// Where a proposed scheduled task runs and posts, when the request names it explicitly.
///
/// `nil` placement on a request means "inherit": a create takes the calling thread's workspace,
/// an edit keeps the definition's own. Only what the model actually asked for is represented
/// here, so inheritance stays the default everywhere.
enum ScheduledTaskProposalPlacement: Equatable, Sendable {
    /// A new-thread run. `flavor` is nil when the request named only a workspace — asking to
    /// switch workspaces, not flavors — so an edit keeps whichever new-thread flavor the
    /// definition already had and a create takes the editor's default.
    case newThread(flavor: ScheduledTaskNewThreadFlavor?, workspace: ScheduledTaskProposalWorkspace?)
    /// Posts into an existing thread, named by its main conversation's id — the same identity
    /// `ScheduledTask.targetThread` resolves from and `list_threads` hands out.
    case existingThread(targetConversationID: String)

    var requestedWorkspace: ScheduledTaskProposalWorkspace? {
        switch self {
        case .newThread(_, let workspace):
            workspace
        case .existingThread:
            nil
        }
    }

    var requestedNewThreadFlavor: ScheduledTaskNewThreadFlavor? {
        switch self {
        case .newThread(let flavor, _):
            flavor
        case .existingThread:
            nil
        }
    }
}

/// Which new-thread behavior a placement asked for, mirroring the editor's two new-thread rows.
enum ScheduledTaskNewThreadFlavor: Equatable, Sendable {
    /// One rolling thread, created on the first run and reused after — the editor's default.
    case reused
    case perRun

    var destination: ScheduledTaskDestination {
        switch self {
        case .reused: .reusedThread
        case .perRun: .newThreadPerRun
        }
    }
}

/// A requested workspace for a new-thread schedule.
///
/// Run location is host-bound: explicit Git folders use worktrees, ordinary folders use Local,
/// and omitted workspace requests preserve the saved strategy.
enum ScheduledTaskProposalWorkspace: Equatable, Sendable {
    /// The path must name a Project already registered in Alveary; an arbitrary path is refused
    /// rather than registered on the fly.
    case project(path: String, grantedRoots: [String]?, isID: Bool = false, primaryFolderPath: String? = nil, privateWorkspace: Bool = false)
    case privateWorkspace(grantedRoots: [String]?)

    /// A complete replacement can repair an unreadable saved workspace without inheriting it.
    var requiresInheritedWorkspace: Bool {
        if case .privateWorkspace(grantedRoots: nil) = self { return true }
        return false
    }

    var kind: ScheduledTaskWorkspaceKind {
        switch self {
        case .project:
            .project
        case .privateWorkspace:
            .privateWorkspace
        }
    }

    var projectPath: String? {
        switch self {
        case .project(let path, _, let isID, _, _):
            isID ? nil : path
        case .privateWorkspace:
            nil
        }
    }

    var projectID: String? {
        if case let .project(key, _, isID, _, _) = self, isID { return key }
        return nil
    }

    var primaryFolderPath: String? {
        if case let .project(_, _, _, path, _) = self { return path }
        return nil
    }

    var requestsPrivateWorkspace: Bool {
        switch self {
        case .project(_, _, _, _, let value): value
        case .privateWorkspace: true
        }
    }

    /// `nil` keeps the inherited grants. A value replaces them and may add folders beyond them,
    /// matching the editor pane; the host validates and discloses every grant before the user
    /// confirms.
    var grantedRoots: [String]? {
        switch self {
        case let .project(_, grantedRoots, _, _, _),
             let .privateWorkspace(grantedRoots):
            grantedRoots
        }
    }
}
