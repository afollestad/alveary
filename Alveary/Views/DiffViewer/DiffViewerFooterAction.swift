import Foundation

/// The Git changes pane footer's action ladder. `available(...)` returns
/// default-first, and that ordering *is* the ladder: Commit leads while the
/// tree is dirty, Push once it is clean, and Create PR / View PR once
/// everything is pushed. Every action still valid stays behind the split
/// button's caret. Modelled on `PullRequestStateAction`.
struct DiffViewerFooterAction: Equatable, Identifiable {
    enum Kind: Hashable {
        case commit
        case push
        case createPullRequest
        case viewPullRequest
    }

    let kind: Kind
    let title: String
    var isEnabled = true

    var id: Kind { kind }

    /// One glyph per kind, shared by the footer's plain button and its split
    /// form. Create PR and View PR deliberately share the pull-request octicon:
    /// both land the user on the same pull request.
    var icon: ActionIcon {
        switch kind {
        case .commit:
            return .octicon("GitCommitOcticon")
        case .push:
            return .octicon("RepoPushOcticon16")
        case .createPullRequest, .viewPullRequest:
            return .octicon("PullRequestOcticon16")
        }
    }

    /// `canCreatePullRequest` and `canViewPullRequest` are mutually exclusive
    /// by construction — the first needs zero linked pull requests and the
    /// second exactly one; several linked leaves both false, and the popover
    /// owns that disambiguation.
    static func available(
        workingState: DiffViewerWorkingState,
        canCommit: Bool,
        canCreatePullRequest: Bool,
        canViewPullRequest: Bool
    ) -> [DiffViewerFooterAction] {
        var actions: [DiffViewerFooterAction] = []
        if canCommit, workingState.hasChanges {
            actions.append(DiffViewerFooterAction(kind: .commit, title: "Commit"))
        }
        // Push is the same working-tree mutation surface as Commit, so it
        // follows the same selection gate.
        if canCommit, workingState.hasUnpushedCommits {
            actions.append(DiffViewerFooterAction(kind: .push, title: "Push changes"))
        }
        if canCreatePullRequest {
            actions.append(DiffViewerFooterAction(kind: .createPullRequest, title: "Create PR"))
        }
        if canViewPullRequest {
            actions.append(DiffViewerFooterAction(kind: .viewPullRequest, title: "View PR"))
        }
        return actions
    }

    /// The zero-available stand-in, so the strip keeps its height rather than
    /// appearing and disappearing — the same reason the pull-request footer
    /// has one.
    static let placeholder = DiffViewerFooterAction(kind: .commit, title: "Commit", isEnabled: false)
}
