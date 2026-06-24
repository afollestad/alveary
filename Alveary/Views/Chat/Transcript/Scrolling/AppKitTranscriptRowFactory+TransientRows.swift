import AppKit

@MainActor
extension AppKitTranscriptRowFactory {
    func streamingBubbleRow(
        text: String,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: AppKitTranscriptTransientRows.streamingRowID, as: AppKitTranscriptStreamingBubbleView.self)
        view.onHeightInvalidated = heightInvalidationHandler(
            for: AppKitTranscriptTransientRows.streamingRowID,
            animatesLayoutChanges: false,
            configuration: configuration
        )
        view.configure(
            .init(
                text: text,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: AppKitTranscriptTransientRows.streamingRowID, view: view)
    }

    func thoughtBubbleRow(
        text: String,
        sequence: Int,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let rowID = AppKitTranscriptTransientRows.thoughtRowID(sequence: sequence)
        let view = cachedView(for: rowID, as: AppKitTranscriptStreamingBubbleView.self)
        view.onHeightInvalidated = heightInvalidationHandler(
            for: rowID,
            animatesLayoutChanges: false,
            configuration: configuration
        )
        view.configure(
            .init(
                text: text,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography,
                variant: .thought
            )
        )
        return .init(id: rowID, view: view)
    }

    func thinkingIndicatorRow(
        transientRows: AppKitTranscriptTransientRows,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: AppKitTranscriptTransientRows.thinkingRowID, as: AppKitTranscriptThinkingIndicatorView.self)
        view.configure(
            .init(
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography,
                isAnimated: transientRows.isThinkingAnimated
            )
        )
        return .init(id: AppKitTranscriptTransientRows.thinkingRowID, view: view)
    }
}
