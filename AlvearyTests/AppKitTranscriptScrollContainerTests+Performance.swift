@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testLargeTranscriptNamedHeightInvalidationRemeasuresOnlyDirtyRow() throws {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
        container.layoutSubtreeIfNeeded()
        let rowViews = (0..<160).map { _ in PerformanceMeasuringHeightRowView(height: 32) }
        let rows = rowViews.enumerated().map { index, view in
            AppKitTranscriptLayoutRow(id: "row-\(index)", view: view)
        }
        container.configure(rows: rows, preserveBottomIfFollowing: false)
        rowViews.forEach { $0.resetMeasurementCount() }

        rowViews[80].height = 72
        container.rowHeightInvalidated(rowID: "row-80", preserveBottomIfFollowing: false, animatesLayoutChanges: false)

        // Guard the long-transcript hot path without relying on wall-clock timing.
        XCTAssertEqual(rowViews[..<80].map(\.measurementCount).reduce(0, +), 0)
        XCTAssertGreaterThan(rowViews[80].measurementCount, 0)
        XCTAssertEqual(rowViews[81...].map(\.measurementCount).reduce(0, +), 0)
        let changedFrame = try XCTUnwrap(container.rowFrame(for: "row-80"))
        let nextFrame = try XCTUnwrap(container.rowFrame(for: "row-81"))
        XCTAssertEqual(changedFrame.height, 72, accuracy: 0.5)
        XCTAssertEqual(nextFrame.minY, changedFrame.maxY + 12, accuracy: 0.5)
    }
}

private final class PerformanceMeasuringHeightRowView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    private(set) var measurementCount = 0

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

    func resetMeasurementCount() {
        measurementCount = 0
    }
}
