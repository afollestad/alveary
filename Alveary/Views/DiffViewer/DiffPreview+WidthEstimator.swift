import AppKit

/// Measures the scrollable width diff rows will actually render at, so the
/// scroll container never reserves horizontal space no row can fill.
enum DiffPreviewWidthEstimator {
    /// Advance of one column in `.system(.caption, design: .monospaced)`, read from
    /// the real font. A hardcoded guess reserved scroll space no row could fill.
    private static let monospacedColumnWidth: CGFloat = {
        ("0" as NSString).size(withAttributes: [.font: monospacedCaptionFont()]).width
    }()

    static func monospacedTextWidth<S: StringProtocol>(
        _ text: S,
        horizontalPadding: CGFloat = 0
    ) -> CGFloat {
        // Tabs land on absolute tab stops rather than fixed columns, and non-ASCII
        // glyphs can be wider than one column, so both take the measured branch.
        let width: CGFloat
        if text.allSatisfy({ $0.isASCII && $0 != "\t" }) {
            width = CGFloat(max(text.count, 1)) * monospacedColumnWidth
        } else {
            width = (String(text) as NSString).size(withAttributes: [.font: monospacedCaptionFont()]).width
        }
        return ceil(width + horizontalPadding)
    }

    static func proportionalCaptionTextWidth(
        _ text: String,
        horizontalPadding: CGFloat = 0
    ) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        let semibold = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: semibold]).width + horizontalPadding)
    }

    static func rawPatchWidth(_ rawDiffContent: String) -> CGFloat {
        rawDiffContent.split(separator: "\n", omittingEmptySubsequences: false)
            .map { monospacedTextWidth($0) }
            .max() ?? 0
    }

    private static func monospacedCaptionFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
    }
}
