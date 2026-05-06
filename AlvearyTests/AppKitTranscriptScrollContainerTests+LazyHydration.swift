@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testOffscreenMarkdownRowsRemainShellsAfterInitialConfigure() throws {
        let container = makeLazyHydrationContainer(height: 80)
        let rowViews = makeLazyMarkdownRows(count: 14)

        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)

        XCTAssertTrue(rowViews[0].isMarkdownHydratedForTesting)
        XCTAssertFalse(try XCTUnwrap(rowViews.last).isMarkdownHydratedForTesting)
        XCTAssertLessThan(rowViews.filter(\.isMarkdownHydratedForTesting).count, rowViews.count)
    }

    func testVisiblePrefetchRowsHydrateAfterScroll() throws {
        let container = makeLazyHydrationContainer(height: 80)
        let rowViews = makeLazyMarkdownRows(count: 14)
        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)

        let lastRow = try XCTUnwrap(rowViews.last)
        XCTAssertFalse(lastRow.isMarkdownHydratedForTesting)

        container.scrollToBottom()

        XCTAssertTrue(lastRow.isMarkdownHydratedForTesting)
    }

    func testViewportHydrationDoesNotChangeDocumentHeight() {
        let container = makeLazyHydrationContainer(height: 80)
        let rowViews = makeLazyMarkdownRows(count: 14)
        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)
        let documentHeightBeforeScroll = container.documentHeight

        container.scrollToBottom()

        XCTAssertEqual(container.documentHeight, documentHeightBeforeScroll, accuracy: 0.5)
    }

    func testHydratingAboveVisibleAnchorPreservesRowIdentityAndOffset() throws {
        let container = makeLazyHydrationContainer(height: 90)
        let rowViews = makeLazyMarkdownRows(count: 16)
        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)
        let anchorFrame = try XCTUnwrap(container.rowFrame(for: "lazy-10"))
        let anchor = AppKitTranscriptVisibleAnchor(
            rowID: "lazy-10",
            offsetWithinRow: min(12, anchorFrame.height / 2),
            generation: container.paginationGeneration
        )

        XCTAssertTrue(container.restoreVisibleAnchor(anchor))

        let restoredFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, restoredFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
        XCTAssertTrue(rowViews[8].isMarkdownHydratedForTesting)
        XCTAssertTrue(rowViews[10].isMarkdownHydratedForTesting)
    }

    func testBottomFollowingModeStaysPinnedWhenHydratingBottomRows() throws {
        let container = makeLazyHydrationContainer(height: 90)
        let rowViews = makeLazyMarkdownRows(count: 16)
        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)

        container.scrollToBottom()

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        XCTAssertTrue(try XCTUnwrap(rowViews.last).isMarkdownHydratedForTesting)
    }

    func testRapidScrollingHydratesVisitedRows() throws {
        let container = makeLazyHydrationContainer(height: 90)
        let rowViews = makeLazyMarkdownRows(count: 18)
        container.configure(rows: layoutRows(for: rowViews), preserveBottomIfFollowing: false)

        for index in stride(from: 0, to: rowViews.count, by: 3) {
            let rowID = "lazy-\(index)"
            let frame = try XCTUnwrap(container.rowFrame(for: rowID))
            let anchor = AppKitTranscriptVisibleAnchor(
                rowID: rowID,
                offsetWithinRow: min(8, frame.height / 2),
                generation: container.paginationGeneration
            )
            XCTAssertTrue(container.restoreVisibleAnchor(anchor))
            XCTAssertTrue(rowViews[index].isMarkdownHydratedForTesting)
        }
    }
}

@MainActor
private func makeLazyHydrationContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
    let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
    container.layoutSubtreeIfNeeded()
    return container
}

@MainActor
private func makeLazyMarkdownRows(count: Int) -> [AppKitTranscriptTextBubbleRowView] {
    (0..<count).map { index in
        let row = AppKitTranscriptTextBubbleRowView()
        row.hydratesMarkdownImmediately = false
        row.configure(
            .init(
                id: "lazy-\(index)",
                role: .assistant,
                markdown: "Viewport hydrated row \(index) with `inline code` and [docs](README.md).",
                bubbleMaxWidth: 300
            )
        )
        return row
    }
}

@MainActor
private func layoutRows(for rowViews: [AppKitTranscriptTextBubbleRowView]) -> [AppKitTranscriptLayoutRow] {
    rowViews.enumerated().map { index, rowView in
        AppKitTranscriptLayoutRow(id: "lazy-\(index)", view: rowView)
    }
}
