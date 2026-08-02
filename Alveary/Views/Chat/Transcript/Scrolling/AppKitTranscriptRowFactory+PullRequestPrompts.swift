import AppKit

extension AppKitTranscriptRowFactory {
    /// One row per unanswered pull-request link prompt anchored to this message,
    /// stacked below its bubble and aligned with it.
    func pullRequestLinkPromptRows(
        messageID: String,
        alignment: AppKitTranscriptPullRequestPromptView.Alignment,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        guard let prompts = configuration.pullRequestLinkPromptsByMessageID[messageID] else {
            return []
        }
        return prompts.map { prompt in
            let rowID = "\(messageID)-pr-prompt-\(prompt.identifier.displayKey)"
            let view = cachedView(for: rowID, as: AppKitTranscriptPullRequestPromptView.self)
            let selection = configuration.selectedPullRequestPromptSelection(prompt.id)
            view.onHeightInvalidated = heightInvalidationHandler(for: rowID, configuration: configuration)
            view.onAccept = { always in
                configuration.onAcceptPullRequestLinkPrompt(prompt, always)
            }
            view.onDecline = { never in
                configuration.onDeclinePullRequestLinkPrompt(prompt, never)
            }
            view.onSelectionChanged = { selection in
                configuration.onSelectPullRequestPromptSelection(prompt.id, selection)
            }
            view.configure(
                .init(
                    promptID: prompt.id,
                    displayKey: prompt.identifier.displayKey,
                    alignment: alignment,
                    selection: selection,
                    maxWidth: configuration.bubbleMaxWidth,
                    typography: configuration.typography
                )
            )
            return .init(id: rowID, view: view)
        }
    }
}
