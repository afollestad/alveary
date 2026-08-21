import AppKit
import SwiftUI
import XCTest

@testable import Alveary

/// Vertical companion to `SnapshotTests+DiffViewerScroll`, which guards the scrollable *width*.
/// The scroll container proposes nil in both axes, so height needs the same guarding: `LazyVStack`
/// answers a nil height proposal with an estimate, sizing rows it has not built from the mean of
/// the realized window. One 127pt comment card among ~21pt line rows inflated every unrealized row
/// and left thousands of points of empty scroll space below the last row of a commented pull
/// request diff. `FlattenedDiffPreviewHeightPlan` replaces that estimate with a counted total.
@MainActor
extension SnapshotTests {
    /// The estimate's signature was that the reported content height moved as rows realized and
    /// were released. A counted total cannot: the same diff reports one height from any offset.
    func testDiffViewerContentHeightDoesNotChangeWithScrollPosition() throws {
        let host = DiffPreviewScrollHost(
            Self.commentedDiffPreview(threadCount: 3),
            size: CGSize(width: 600, height: 444)
        )
        defer { host.close() }
        host.pumpRunLoop(seconds: 0.3)

        let scrollView = try host.scrollView()
        let atTop = try XCTUnwrap(scrollView.documentView).frame.height
        try host.scrollToBottom(scrollView)
        let atBottom = try XCTUnwrap(scrollView.documentView).frame.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        host.pumpRunLoop()
        let backAtTop = try XCTUnwrap(scrollView.documentView).frame.height

        XCTAssertEqual(atTop, atBottom, accuracy: 0.5)
        XCTAssertEqual(atTop, backAtTop, accuracy: 0.5)

        // A total that fell *short* of what the rows draw would strand the last of them outside the
        // scroll range, so guard the floor too: 640 line rows cannot fit in less than 18pt each.
        XCTAssertGreaterThan(atBottom, 640 * 18)
    }

    /// Comment rows must cost their own height and nothing more. They used to cost that plus a
    /// per-row surcharge on every other row in the diff, which is what pooled as dead space.
    func testDiffViewerCommentRowsCostOnlyTheirOwnHeight() throws {
        let plain = try Self.contentHeight(threadCount: 0)
        let threaded = try Self.contentHeight(threadCount: 3)

        // Three cards, each ~127pt drawn. The bound is loose enough to survive a card redesign and
        // far tighter than what three threads cost while the height was estimated — that surcharge
        // scaled with the row count, so this fixture is wide on purpose.
        XCTAssertGreaterThan(threaded, plain)
        XCTAssertLessThan(threaded - plain, 3 * 260)
    }

    private static func contentHeight(threadCount: Int) throws -> CGFloat {
        let host = DiffPreviewScrollHost(
            commentedDiffPreview(threadCount: threadCount),
            size: CGSize(width: 600, height: 444)
        )
        defer { host.close() }
        host.pumpRunLoop(seconds: 0.3)
        let scrollView = try host.scrollView()
        try host.scrollToBottom(scrollView)
        return try XCTUnwrap(scrollView.documentView).frame.height
    }

    /// Threads anchor to the first added line of the leading files, so the tall cards land in the
    /// realized window at the top — the shape that poisoned the estimate for everything below.
    ///
    /// **Keep the cards identical to each other.** Only the first is realized before the initial
    /// measurement; the rest borrow its height until they are drawn, so cards of differing heights
    /// would move the total between the top and the bottom for a legitimate reason and read as the
    /// regression this file guards.
    private static func commentedDiffPreview(threadCount: Int) -> some View {
        var annotations = DiffCommentAnnotations()
        for index in 0..<threadCount {
            let anchor = DiffCommentAnchor(path: "File\(index).swift", side: .right, line: 1)
            annotations.threads[anchor] = DiffLineCommentThread(
                comments: [
                    DiffLineComment(
                        author: "priya",
                        bodyMarkdown: "Clamp this before the fetch.",
                        isPending: false,
                        remoteID: 900 + index,
                        nodeID: "PRRC_\(index)"
                    )
                ],
                threadID: "PRT_\(index)"
            )
        }

        return FlattenedDiffPreview(
            files: DiffParser.parse(makeUnifiedDiffFixture(fileCount: 8, addedLinesPerFile: 80)),
            showsFileHeaders: true,
            allowsFileCollapse: true,
            commentAnnotations: annotations
        )
    }
}
