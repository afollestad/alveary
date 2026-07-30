import SwiftUI

extension FlattenedDiffPreviewRows {
    static func minimumScrollableContentWidth(for rows: [FlattenedDiffPreviewRow]) -> CGFloat {
        rows.reduce(0) { width, row in
            max(width, minimumScrollableContentWidth(for: row))
        }
    }

    private static func minimumScrollableContentWidth(for row: FlattenedDiffPreviewRow) -> CGFloat {
        switch row {
        case .fileHeader:
            // The header frames to the exact content width and middle-truncates
            // its path, so it can never fill scroll space it requested.
            return 0
        case .renameSummary(_, let oldPath, let newPath):
            return max(
                DiffPreviewWidthEstimator.monospacedTextWidth(oldPath, horizontalPadding: 24),
                DiffPreviewWidthEstimator.monospacedTextWidth(newPath, horizontalPadding: 24)
            )
        case .imagePreview, .binaryCallout, .emptyCallout, .fileContentSpacer:
            return 0
        case .commentThread, .commentComposer:
            // Comment content wraps at the viewport instead of extending scrollable width.
            return 0
        case .hunkHeader(_, let hunk, _):
            return DiffPreviewWidthEstimator.monospacedTextWidth(hunkHeaderText(for: hunk), horizontalPadding: 24)
        case .line(_, let line, let gutterLayout, _, _, _):
            return gutterWidth(for: gutterLayout) + DiffPreviewWidthEstimator.monospacedTextWidth(
                line.content.isEmpty ? " " : line.content,
                horizontalPadding: 20
            )
        case .collapsed(_, let summary, let gutterLayout, _, _):
            // The omitted-lines text renders proportional semibold caption, not monospaced.
            return gutterWidth(for: gutterLayout) + DiffPreviewWidthEstimator.proportionalCaptionTextWidth(
                omittedText(for: summary),
                horizontalPadding: 20
            )
        }
    }

    private static func hunkHeaderText(for hunk: DiffHunk) -> String {
        let oldRange = rangeText(prefix: "-", start: hunk.oldStart, count: hunk.oldCount)
        let newRange = rangeText(prefix: "+", start: hunk.newStart, count: hunk.newCount)
        let suffix = hunk.header.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
        return "@@ \(oldRange) \(newRange) @@\(suffix)"
    }

    private static func rangeText(prefix: String, start: Int, count: Int) -> String {
        if count == 1 {
            return "\(prefix)\(start)"
        }
        return "\(prefix)\(start),\(count)"
    }

    private static func omittedText(for summary: CollapsedContextSummary) -> String {
        guard summary.addedCount > 0 || summary.deletedCount > 0 else {
            return "\(summary.lineCount) unchanged lines hidden"
        }

        let changeCounts = [
            summary.addedCount > 0 ? "+\(summary.addedCount)" : nil,
            summary.deletedCount > 0 ? "-\(summary.deletedCount)" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return "\(summary.lineCount) diff lines hidden (\(changeCounts))"
    }

    private static func gutterWidth(for gutterLayout: DiffGutterLayout) -> CGFloat {
        let oldWidth = gutterLayout.showsOldLineNumbers ? gutterLayout.lineNumberWidth + gutterLayout.lineNumberTrailingPadding : 0
        let newWidth = gutterLayout.showsNewLineNumbers ? gutterLayout.lineNumberWidth + gutterLayout.lineNumberTrailingPadding : 0
        return oldWidth + newWidth + gutterLayout.markerWidth + 1
    }
}
