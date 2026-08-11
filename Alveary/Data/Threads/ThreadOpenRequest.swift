import Foundation

/// Asks the app root to select the thread a transcript card names.
///
/// Transcript rows are AppKit views inside `ChatTranscriptView`, which owns neither the sidebar
/// selection nor the model context that says whether the thread is still live, so the ask travels
/// as a notification the way `PullRequestPaneRequest` does. Selection is app-wide rather than
/// pane-scoped, so this carries no originating thread.
struct ThreadOpenRequest: Equatable {
    /// Sole-main-conversation id, the same handle the thread host tools take.
    let conversationID: String
}

enum ThreadOpenRequestNotificationKey {
    static let request = "request"
}

extension Notification.Name {
    static let threadOpenRequested = Notification.Name("threadOpenRequested")
}
