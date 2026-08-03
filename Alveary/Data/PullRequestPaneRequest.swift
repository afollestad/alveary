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
}

enum PullRequestPaneRequestNotificationKey {
    static let request = "request"
}

extension Notification.Name {
    static let pullRequestPaneRequested = Notification.Name("pullRequestPaneRequested")
}
