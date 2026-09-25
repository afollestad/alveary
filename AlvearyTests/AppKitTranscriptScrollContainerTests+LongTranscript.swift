@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// Long-transcript guards: every check here bounds work by the viewport or the dirty row, never
/// by the transcript's length, without relying on wall-clock timing.
@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testLongTranscriptScrollToBottomHydratesOnlyViewportRows() {
        let fixture = LongTranscriptFixture(rowCount: 2_000)
        fixture.container.configure(rows: fixture.rows, preserveBottomIfFollowing: false)

        fixture.container.scrollToBottom()

        let hydratedIndices = fixture.rowViews.indices.filter { fixture.rowViews[$0].isTranscriptViewportHydrated }
        XCTAssertTrue(hydratedIndices.contains(fixture.rowViews.count - 1))
        // Configure hydrated the first viewport at the top; the scroll hydrated the last one. Each is
        // the viewport plus a 1.5× margin, at 32pt rows and 12pt spacing, and nothing in between.
        XCTAssertLessThan(hydratedIndices.count, 120)
        XCTAssertTrue(hydratedIndices.filter { (100..<1_900).contains($0) }.isEmpty)
    }

    func testLongTranscriptUnchangedHeightInvalidationTouchesOnlyTheDirtyRow() {
        let fixture = LongTranscriptFixture(rowCount: 2_000)
        fixture.container.configure(rows: fixture.rows, preserveBottomIfFollowing: false)
        fixture.container.scrollToBottom()
        fixture.rowViews.forEach { $0.resetCounts() }
        let lastID = fixture.rows[fixture.rows.count - 1].id

        fixture.container.rowHeightInvalidated(rowID: lastID, preserveBottomIfFollowing: true, animatesLayoutChanges: false)

        XCTAssertEqual(fixture.rowViews.dropLast().map(\.measurementCount).reduce(0, +), 0)
        XCTAssertGreaterThan(fixture.rowViews[fixture.rowViews.count - 1].measurementCount, 0)
        XCTAssertEqual(fixture.rowViews.map(\.hydrationCount).reduce(0, +), 0)
    }

    func testLongTranscriptGrowingLastRowRehydratesNothingAboveTheViewport() {
        let fixture = LongTranscriptFixture(rowCount: 2_000)
        fixture.container.configure(rows: fixture.rows, preserveBottomIfFollowing: false)
        fixture.container.scrollToBottom()
        fixture.rowViews.forEach { $0.resetCounts() }
        let lastIndex = fixture.rows.count - 1

        fixture.rowViews[lastIndex].height = 96
        fixture.container.rowHeightInvalidated(rowID: fixture.rows[lastIndex].id, preserveBottomIfFollowing: true, animatesLayoutChanges: false)

        XCTAssertEqual(fixture.rowViews[..<(lastIndex - 60)].map(\.hydrationCount).reduce(0, +), 0)
        XCTAssertEqual(fixture.container.rowFrame(for: fixture.rows[lastIndex].id)?.height ?? 0, 96, accuracy: 0.5)
        XCTAssertEqual(fixture.container.visibleBottomY, fixture.container.documentHeight, accuracy: 0.5)
    }

    func testOrderedRowFrameQueriesMatchLinearScans() throws {
        let fixture = LongTranscriptFixture(rowCount: 500)
        fixture.container.configure(rows: fixture.rows, preserveBottomIfFollowing: false)
        let document = fixture.container.transcriptDocumentView
        let frames = try fixture.rows.map { try XCTUnwrap(fixture.container.rowFrame(for: $0.id)) }

        XCTAssertEqual(document.scrollableContentBottomY, try XCTUnwrap(frames.map(\.maxY).max()), accuracy: 0.5)
        for offsetY in [-10, 0, 19.5, 20, 52, 1_000, 13_337.2, frames[frames.count - 1].maxY, 1_000_000] {
            let expected = frames.firstIndex { $0.maxY >= offsetY }.map { fixture.rows[$0].id }
            XCTAssertEqual(document.firstRow(atOrBelow: offsetY)?.id, expected, "offsetY \(offsetY)")
            let rect = CGRect(x: 0, y: offsetY, width: 300, height: 333)
            let expectedIntersecting = frames.indices.filter { frames[$0].intersects(rect) }.map { fixture.rows[$0].id }
            XCTAssertEqual(document.rowFrames(intersecting: rect).map(\.id), expectedIntersecting, "rect \(rect)")
        }
    }
}

@MainActor
private struct LongTranscriptFixture {
    let container: AppKitTranscriptScrollContainerView
    let rowViews: [LongTranscriptRowView]
    let rows: [AppKitTranscriptLayoutRow]

    init(rowCount: Int) {
        container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        container.layoutSubtreeIfNeeded()
        rowViews = (0..<rowCount).map { _ in LongTranscriptRowView(height: 32) }
        rows = rowViews.enumerated().map { index, view in
            AppKitTranscriptLayoutRow(id: "row-\(index)", view: view)
        }
    }
}

private final class LongTranscriptRowView: NSView, AppKitTranscriptViewportHydratable {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
    private(set) var measurementCount = 0
    private(set) var hydrationCount = 0
    private(set) var isTranscriptViewportHydrated = false

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var fittingSize: NSSize {
        measurementCount += 1
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    func hydrateForTranscriptViewport() {
        hydrationCount += 1
        isTranscriptViewportHydrated = true
    }

    func resetCounts() {
        measurementCount = 0
        hydrationCount = 0
    }
}
