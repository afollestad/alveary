import AppKit
import XCTest

@testable import Alveary

final class FlattenedDiffPreviewWidthTests: XCTestCase {
    /// The advance the estimator must match, measured from the same font the
    /// diff rows render with.
    private var measuredAdvance: CGFloat {
        let pointSize = NSFont.preferredFont(forTextStyle: .caption1).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }

    func testAsciiWidthMatchesMeasuredFontAdvance() {
        XCTAssertEqual(
            DiffPreviewWidthEstimator.monospacedTextWidth("abcdef"),
            ceil(6 * measuredAdvance)
        )
    }

    func testTabsAndNonAsciiUseExactMeasurement() {
        // SwiftUI lays tabs out on absolute tab stops, wider than four columns.
        XCTAssertGreaterThanOrEqual(
            DiffPreviewWidthEstimator.monospacedTextWidth("\t"),
            ceil(4 * measuredAdvance)
        )

        // CJK glyphs are wider than one monospaced column.
        XCTAssertGreaterThan(
            DiffPreviewWidthEstimator.monospacedTextWidth("日本語"),
            ceil(3 * measuredAdvance)
        )
    }

    func testShortLineDiffFitsTypicalPaneWidth() {
        let width = FlattenedDiffPreviewRows.makeRows(
            files: DiffParser.parse(Self.shortLineDiff(path: "scripts/scroll-to-experience.js")),
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        ).minimumScrollableContentWidth

        // 73 monospaced characters plus gutters measure ~545pt; the retired
        // 8pt-per-character guess reported 677pt and forced phantom scrolling.
        XCTAssertGreaterThan(width, 450)
        XCTAssertLessThan(width, 560)
    }

    func testFileHeaderContributesNoScrollableWidth() {
        let longPath = String(repeating: "nested-directory/", count: 12) + "file.js"
        let baseline = FlattenedDiffPreviewRows.makeRows(
            files: DiffParser.parse(Self.shortLineDiff(path: "file.js")),
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        )
        let longPathRows = FlattenedDiffPreviewRows.makeRows(
            files: DiffParser.parse(Self.shortLineDiff(path: longPath)),
            imagePreviews: [:],
            showsFileHeaders: true,
            allowsFileCollapse: false,
            collapsedFileIDs: []
        )

        XCTAssertEqual(longPathRows.minimumScrollableContentWidth, baseline.minimumScrollableContentWidth)
    }

    private static func shortLineDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1,4 +1,5 @@
         (function () {
        +    // Keep the experience shortcut inert when its target is not present.
        """
    }
}
