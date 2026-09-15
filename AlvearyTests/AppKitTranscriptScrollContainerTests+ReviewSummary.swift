import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testReviewSummaryEditingOnlyInvalidatesItsOwnRowInALargeTranscript() async throws {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        let proposal = ReviewProposalSnapshotFixture.widgetRow()
        let neighbors = (0..<159).map { _ in ReviewSummaryMeasuringRow() }
        var rows = neighbors.enumerated().map { AppKitTranscriptLayoutRow(id: "neighbor-\($0.offset)", view: $0.element) }
        rows.insert(.init(id: "proposal", view: proposal), at: 80)
        proposal.onImmediateHeightInvalidated = { [weak container] in
            container?.rowHeightInvalidated(rowID: "proposal", preserveBottomIfFollowing: false, animatesLayoutChanges: false)
        }
        container.configure(rows: rows, preserveBottomIfFollowing: false)
        XCTAssertTrue(container.scrollToRowTop(rowID: "proposal"))
        neighbors.forEach { $0.measurements = 0 }
        let summary = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: proposal) { $0 is AppKitReviewProposalSummaryView }
            as? AppKitReviewProposalSummaryView)
        XCTAssertNil(summary.editor)
        let before = try XCTUnwrap(container.rowFrame(for: "proposal"))
        summary.beginEditing()
        let editor = try XCTUnwrap(summary.editor)
        let deadline = Date().addingTimeInterval(2)
        while !(window.firstResponder is NSTextView), Date() < deadline {
            window.displayIfNeeded()
            await Task.yield()
        }
        XCTAssertNotEqual(container.rowFrame(for: "proposal")?.height, before.height)
        XCTAssertEqual(neighbors.map(\.measurements).reduce(0, +), 0)

        let height = container.documentHeight
        var invalidations = 0
        proposal.onImmediateHeightInvalidated = { invalidations += 1 }
        // A short edit stays within the two-line minimum and must not touch list geometry.
        guard let text = window.firstResponder as? NSTextView else {
            XCTFail("The visible proposal editor must receive focus")
            return
        }
        text.insertText("Short edit", replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        for _ in 0..<100 {
            container.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        XCTAssertEqual(invalidations, 0)
        XCTAssertEqual(container.documentHeight, height)
        XCTAssertEqual(neighbors.map(\.measurements).reduce(0, +), 0)
        XCTAssertTrue(summary.editor === editor)
        await assertCappedTyping(container: container, proposal: proposal, text: text, rows: rows, neighbors: neighbors)
        summary.cancel()
    }

    private func assertCappedTyping(
        container: AppKitTranscriptScrollContainerView, proposal: AppKitTranscriptHostToolWidgetRowView,
        text: NSTextView, rows: [AppKitTranscriptLayoutRow], neighbors: [ReviewSummaryMeasuringRow]
    ) async {
        var invalidations = 0
        let growth = expectation(description: "Editor grows to its cap")
        var awaitingGrowth = true
        proposal.onImmediateHeightInvalidated = { [weak container] in
            invalidations += 1
            if awaitingGrowth { awaitingGrowth = false; growth.fulfill() }
            container?.rowHeightInvalidated(rowID: "proposal", preserveBottomIfFollowing: false, animatesLayoutChanges: false)
        }
        text.insertText(String(repeating: "Long comment ", count: 200), replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        await fulfillment(of: [growth], timeout: 3)
        container.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(invalidations, 0)
        let cappedHeight = container.documentHeight
        let downstreamFrames = rows.dropFirst(81).compactMap { container.rowFrame(for: $0.id) }
        invalidations = 0
        text.insertText(String(repeating: "Long comment ", count: 400), replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        for _ in 0..<100 { container.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertEqual(invalidations, 0)
        XCTAssertEqual(container.documentHeight, cappedHeight)
        XCTAssertEqual(rows.dropFirst(81).compactMap { container.rowFrame(for: $0.id) }, downstreamFrames)
        XCTAssertEqual(neighbors.map(\.measurements).reduce(0, +), 0)
    }
}

private final class ReviewSummaryMeasuringRow: NSView {
    var measurements = 0

    override var fittingSize: NSSize {
        measurements += 1
        return NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }
}
