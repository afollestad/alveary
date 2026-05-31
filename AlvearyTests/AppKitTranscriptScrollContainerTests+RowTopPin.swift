@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testScrollToRowTopPinsRequestedRowAtViewportTop() throws {
        let container = rowTopPinContainer(height: 120)
        container.configure(
            rows: [
                rowTopPinRow("first", height: 80),
                rowTopPinRow("prompt", height: 160),
                rowTopPinRow("thinking", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let promptFrame = try XCTUnwrap(container.rowFrame(for: "prompt"))
        XCTAssertGreaterThan(abs(container.scrollOffsetY - promptFrame.minY), 1)

        XCTAssertTrue(container.scrollToRowTop(rowID: "prompt", topInset: 0))

        XCTAssertEqual(container.scrollOffsetY, promptFrame.minY, accuracy: 0.5)
    }

    private func rowTopPinContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func rowTopPinRow(_ id: String, height: CGFloat) -> AppKitTranscriptLayoutRow {
        AppKitTranscriptLayoutRow(id: id, view: RowTopPinFixedHeightRowView(height: height))
    }
}

private final class RowTopPinFixedHeightRowView: NSView {
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
}
