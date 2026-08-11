import SwiftUI

/// Handles pull-request links detected in transcript messages by
/// `ConversationViewModel+PullRequestDetection`. Detection runs per conversation but
/// only `PullRequestLinksViewModel` may write links, so the request arrives here as
/// a notification.
extension ContentView {
    func handlePullRequestLinkRequest(_ notification: Notification) {
        guard settingsService.current.pullRequestsEnabled,
              let request = notification.userInfo?[
                PullRequestLinkRequestNotificationKey.request
              ] as? PullRequestLinkRequest else {
            return
        }

        Task {
            do {
                try await pullRequestLinksViewModel.linkDetectedPullRequest(
                    request.identifier,
                    threadID: request.threadID
                )
            } catch {
                appState.presentUnexpectedError(message: error.localizedDescription)
            }
        }
    }
}
