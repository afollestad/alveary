import Foundation

/// Where a proposed scheduled task runs and posts, when the request names it explicitly.
///
/// `nil` placement on a request means "inherit": a create takes the calling thread's workspace,
/// an edit keeps the definition's own. Only what the model actually asked for is represented
/// here, so inheritance stays the default everywhere.
enum ScheduledTaskProposalPlacement: Equatable, Sendable {
    case newThread(workspace: ScheduledTaskProposalWorkspace?)
    /// Posts into an existing thread, named by its main conversation's id — the same identity
    /// `ScheduledTask.targetThread` resolves from and `list_threads` hands out.
    case existingThread(targetConversationID: String)

    var requestedWorkspace: ScheduledTaskProposalWorkspace? {
        switch self {
        case .newThread(let workspace):
            workspace
        case .existingThread:
            nil
        }
    }
}

/// A requested workspace for a new-thread schedule.
///
/// Run location is deliberately absent: a local-checkout schedule would mutate the user's real
/// working copy unattended, so it stays host-bound to a worktree.
enum ScheduledTaskProposalWorkspace: Equatable, Sendable {
    /// The path must name a Project already registered in Alveary; an arbitrary path is refused
    /// rather than registered on the fly.
    case project(path: String, grantedRoots: [String]?)
    case privateWorkspace(grantedRoots: [String]?)

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
        case .project(let path, _):
            path
        case .privateWorkspace:
            nil
        }
    }

    /// `nil` keeps the inherited grants. A value replaces them and may add folders beyond them,
    /// matching the editor pane; the host validates and discloses every grant before the user
    /// confirms.
    var grantedRoots: [String]? {
        switch self {
        case let .project(_, grantedRoots),
             let .privateWorkspace(grantedRoots):
            grantedRoots
        }
    }
}
