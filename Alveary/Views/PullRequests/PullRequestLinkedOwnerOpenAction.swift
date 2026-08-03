import SwiftUI

/// Host-provided handler that selects a linked thread or project in the
/// sidebar. The pane reaches neither `AppState` nor a `ModelContext`, so
/// `ContentView` injects this at the mount and re-resolves the owner itself.
/// Equality compares only the stable `id` and excludes the closure, so a host
/// rebuilding the action on every render does not invalidate the pane's
/// environment.
struct PullRequestLinkedOwnerOpenAction: Equatable, Sendable {
    let id: String
    let perform: @MainActor @Sendable (PullRequestLinkOwner) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor
    func callAsFunction(_ owner: PullRequestLinkOwner) {
        perform(owner)
    }
}

private struct PullRequestLinkedOwnerOpenActionKey: EnvironmentKey {
    static let defaultValue: PullRequestLinkedOwnerOpenAction? = nil
}

extension EnvironmentValues {
    /// When set, a linked-owner row selects its thread or project in the
    /// sidebar; with no action injected the rows render inert.
    var pullRequestLinkedOwnerOpenAction: PullRequestLinkedOwnerOpenAction? {
        get { self[PullRequestLinkedOwnerOpenActionKey.self] }
        set { self[PullRequestLinkedOwnerOpenActionKey.self] = newValue }
    }
}
