import Foundation

extension ChatTranscriptView {
    /// Wires the pull-request link widgets' one action: opening the pull request the card
    /// names. The transcript cannot open the pane itself, so the ask goes to the app root
    /// scoped to this transcript's thread.
    func configureAppKitPullRequestWidgets(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        let threadID = viewModel.conversation.thread?.persistentModelID
        configuration.pendingPullRequestLookup = appState.pendingPullRequestPaneLookup.flatMap { lookup in
            lookup.threadID == threadID ? lookup.identifier : nil
        }
        configuration.onOpenPullRequest = { identifier in
            guard let threadID else {
                return
            }
            NotificationCenter.default.post(
                name: .pullRequestPaneRequested,
                object: nil,
                userInfo: [
                    PullRequestPaneRequestNotificationKey.request: PullRequestPaneRequest(
                        identifier: identifier,
                        threadID: threadID
                    )
                ]
            )
        }
    }
}
