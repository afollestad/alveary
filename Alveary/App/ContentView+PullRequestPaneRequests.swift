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
        // it has no stored summary and the pane fetches its own.
        if let row = selectedPullRequestLinks.first(where: { $0.id == request.identifier }) {
            openLinkedPullRequest(row)
            return
        }
        appState.hideDiffViewer()
        // Marked before the hop so the card's spinner appears on the click's own cycle; the
        // fetch is a `gh` round trip, which is exactly the wait the card has to account for.
        appState.beginPullRequestPaneLookup(request)
        Task {
            await pullRequestsViewModel.requestDetails(
                request.identifier,
                origin: .thread(request.threadID)
            )
            appState.endPullRequestPaneLookup(request)
        }
    }
}
