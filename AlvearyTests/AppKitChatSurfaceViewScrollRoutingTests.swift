@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatSurfaceViewScrollRoutingTests: XCTestCase {
    func testScrollWheelOverSurfaceOverlayDoesNotForwardToTranscriptContent() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = RecordingScrollView()
        content.hasVerticalScroller = true
        content.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let composer = FixedHeightView(height: 44)
        let overlay = RecordingOverlayView(frame: NSRect(x: 20, y: 80, width: 260, height: 80))

        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()
        surface.addSubview(overlay, positioned: .above, relativeTo: nil)

        surface.scrollWheel(with: TestSurfaceScrollWheelEvent(location: NSPoint(x: 40, y: 100), deltaY: -8))

        XCTAssertEqual(overlay.scrollWheelCount, 1)
        XCTAssertEqual(content.scrollWheelCount, 0)
    }

    func testScrollWheelOverTranscriptContentStillForwardsToTranscriptScrollView() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = RecordingScrollView()
        content.hasVerticalScroller = true
        content.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let composer = FixedHeightView(height: 44)

        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        surface.scrollWheel(with: TestSurfaceScrollWheelEvent(location: NSPoint(x: 40, y: 100), deltaY: -8))

        XCTAssertEqual(content.scrollWheelCount, 1)
    }
}

private final class FixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }
}

private final class RecordingScrollView: NSScrollView {
    var scrollWheelCount = 0

    override func scrollWheel(with event: NSEvent) {
        scrollWheelCount += 1
    }
}

private final class RecordingOverlayView: NSView {
    var scrollWheelCount = 0

    override func scrollWheel(with event: NSEvent) {
        scrollWheelCount += 1
    }
}

private final class TestSurfaceScrollWheelEvent: NSEvent {
    private let testLocationInWindow: NSPoint
    private let testScrollingDeltaY: CGFloat

    init(location: NSPoint, deltaY: CGFloat) {
        testLocationInWindow = location
        testScrollingDeltaY = deltaY
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var type: NSEvent.EventType {
        .scrollWheel
    }

    override var locationInWindow: NSPoint {
        testLocationInWindow
    }

    override var scrollingDeltaY: CGFloat {
        testScrollingDeltaY
    }

    override var scrollingDeltaX: CGFloat {
        0
    }
}
