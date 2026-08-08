import SwiftUI

/// Opens a pull request asked for from a thread's transcript, where the pull-request link
/// widgets live. Only the root owns the pane lane, so the request arrives as a notification.
extension ContentView {
    func handlePullRequestPaneRequest(_ notification: Notification) {
        guard settingsService.current.pullRequestsEnabled,
              let request = notification.userInfo?[
                PullRequestPaneRequestNotificationKey.request
              ] as? PullRequestPaneRequest,
              // The pane is scoped to the surface that opened it, so a transcript whose
              // thread is no longer selected has nowhere to render one.
              selectedPullRequestLinkOwner == .thread(request.threadID) else {
            return
        }

        // A still-linked pull request opens through the ordinary path, which also refreshes
        // the stored snapshot. An unlink card names one that is deliberately not linked, so
        // it has no stored summary and the pane loads its own detail.
        if let row = selectedPullRequestLinks.first(where: { $0.id == request.identifier }) {
            openLinkedPullRequest(row)
        } else {
            appState.hideDiffViewer()
            pullRequestsViewModel.requestDetails(request.identifier, origin: .thread(request.threadID))
        }

        // Applies to both opens. The agentic review links its pull request before dispatching, so
        // a jump from its transcript card takes the linked branch above — but a review asked for
        // in an existing thread need not be linked, so the identifier branch needs it too. The
        // pane finds the proposal itself; only the scroll comes from the request.
        if let anchor = request.commentAnchor {
            pullRequestsViewModel.requestCommentScroll(to: anchor, target: .details(request.identifier))
        }
    }
}
