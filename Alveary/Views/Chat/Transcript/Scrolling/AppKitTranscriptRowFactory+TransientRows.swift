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

/// Renders only the newest reasoning line. Live thought text accumulates for a whole turn, and
/// providers separate reasoning sections with a blank line, so rendering all of it grows the row
/// without bound and reads as one run-on sentence.
func appKitTranscriptLiveThoughtSummaryText(from text: String) -> String {
    let lines = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: .newlines)
    // Walking backwards keeps the markdown pass off every earlier line of a long accumulation.
    for line in lines.reversed() {
        let collapsed = appKitTranscriptCollapsedLiveThoughtPlainText(
            from: appKitTranscriptLiveThoughtLineText(from: line)
        )
        guard collapsed.isEmpty else {
            return collapsed
        }
    }
    // Every line stripped to nothing, so prefer showing something over an empty row.
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
