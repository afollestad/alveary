@preconcurrency import AppKit
import Foundation
import OSLog

private let textBubbleLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Alveary", category: "TextBubbleLayout")

extension AppKitTranscriptTextBubbleRowView {
    // Fixed-height shells depend on the prepared markdown measurer matching the
    // hydrated AppKit view. A mismatch keeps production usable by routing this
    // row back through the synchronous hydrated measurement path.
    func validateHydratedMarkdownHeight(
        _ markdownView: AppKitMarkdownView,
        metrics: TextBubbleLayoutMetrics
    ) {
        markdownView.layoutSubtreeIfNeeded()
        let hydratedHeight = markdownView.intrinsicContentSize.height
        guard abs(hydratedHeight - metrics.markdownFrame.height) > 0.5 else {
            return
        }
        let configuration = self.configuration
        textBubbleLogger.warning(
            """
            Markdown height mismatch row=\(configuration?.id ?? "nil", privacy: .public) \
            role=\(configuration.map { TextBubblePreparedMeasurement.cacheRole(for: $0.role) } ?? "nil", privacy: .public) \
            markdownClass=\(String(describing: type(of: markdownView)), privacy: .public) \
            width=\(metrics.markdownFrame.width, privacy: .public) \
            bodySize=\(configuration?.typography.body.pointSize ?? 0, privacy: .public) \
            codeSize=\(configuration?.typography.codeBlock.pointSize ?? 0, privacy: .public) \
            measured=\(metrics.markdownFrame.height, privacy: .public) rendered=\(hydratedHeight, privacy: .public)
            """
        )
        forceHydratedMarkdownMeasurement = true
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }
}
