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

    func thoughtRow(
        text: String,
        sequence: Int,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let rowID = AppKitTranscriptTransientRows.thoughtRowID(sequence: sequence)
        let view = cachedView(for: rowID, as: AppKitTranscriptToolHeaderRowView.self)
        view.onHeightInvalidated = heightInvalidationHandler(
            for: rowID,
            animatesLayoutChanges: false,
            configuration: configuration
        )
        view.configure(
            .init(
                summary: appKitTranscriptLiveThoughtSummaryText(from: text),
                leadingIcon: .genericTool,
                phase: .loading,
                showsLeadingIcon: false,
                typography: configuration.typography,
                bottomPadding: transcriptInlineToolRowVerticalPadding,
                maxWidth: configuration.bubbleMaxWidth,
                summaryMaximumNumberOfLines: 0,
                showsStatusSlot: false
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

func appKitTranscriptLiveThoughtSummaryText(from text: String) -> String {
    let lines = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: .newlines)
        .map { appKitTranscriptLiveThoughtLineText(from: $0) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    let collapsed = appKitTranscriptCollapsedLiveThoughtPlainText(from: lines)
    guard collapsed.isEmpty else {
        return collapsed
    }
    return appKitTranscriptCollapsedLiveThoughtPlainText(from: text)
}

private func appKitTranscriptCollapsedLiveThoughtPlainText(from text: String) -> String {
    AppMarkdownInlineLabel.plainText(from: text)
        .replacingOccurrences(of: #"\*{2,}"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"_{2,}"#, with: " ", options: .regularExpression)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func appKitTranscriptLiveThoughtLineText(from line: String) -> String {
    var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.hasPrefix("```"), !result.hasPrefix("~~~") else {
        return ""
    }
    for pattern in liveThoughtBlockPrefixPatterns {
        result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private let liveThoughtBlockPrefixPatterns = [
    #"^#{1,6}\s+"#,
    #"^(?:>\s*)+"#,
    #"^[-*+]\s+\[[xX ]\]\s+"#,
    #"^[-*+]\s+"#,
    #"^\d+[\.)]\s+"#
]
