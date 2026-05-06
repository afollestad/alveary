@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testDirtyRowWithUnchangedHeightDoesNotApplyDownstreamFrames() {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        container.layoutSubtreeIfNeeded()
        let first = NoOpMeasuringHeightRowView(height: 80)
        let second = FrameCountingHeightRowView(height: 80)
        let third = FrameCountingHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second),
                AppKitTranscriptLayoutRow(id: "third", view: third)
            ],
            preserveBottomIfFollowing: false
        )
        first.resetMeasurementCount()
        second.resetFrameCount()
        third.resetFrameCount()

        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)

        XCTAssertGreaterThan(first.measurementCount, 0)
        XCTAssertEqual(second.frameSetCount, 0)
        XCTAssertEqual(third.frameSetCount, 0)
    }
}

private final class NoOpMeasuringHeightRowView: NSView {
    let height: CGFloat
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

private final class FrameCountingHeightRowView: NSView {
    let height: CGFloat
    private(set) var frameSetCount = 0

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override var frame: NSRect {
        didSet {
            frameSetCount += 1
        }
    }

    func resetFrameCount() {
        frameSetCount = 0
    }
}
