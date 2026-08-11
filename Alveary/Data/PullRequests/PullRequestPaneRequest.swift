import Foundation
import SwiftData

/// Asks the app root to open a pull request in the right-pane lane.
///
/// Transcript rows are AppKit views inside `ChatTranscriptView`, which owns neither the
/// browsing view model that holds pane sessions nor the Diff Viewer request the lane shares,
/// so the ask travels as a notification the way `PullRequestLinkRequest` does. `threadID`
/// scopes the pane to the thread whose transcript was clicked.
struct PullRequestPaneRequest: Equatable {
    let identifier: PullRequestIdentifier
    let threadID: PersistentIdentifier
    /// Set when the ask came from a review proposal's staged comment: the pane opens on its
    /// Changes tab scrolled to that comment. It carries no proposal id — the pane resolves a
    /// pending proposal from the pull request itself, so *every* route shows the same staged
    /// comments and only the scroll is particular to a jump.
    var commentAnchor: DiffCommentAnchor?
}

enum PullRequestPaneRequestNotificationKey {
    static let request = "request"
}

extension Notification.Name {
    static let pullRequestPaneRequested = Notification.Name("pullRequestPaneRequested")
}
