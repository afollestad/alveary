@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testRowHeightInvalidationUsesCurrentScrollPositionBeforePreservingBottom() throws {
        let container = bottomPreservationContainer(height: 120)
        let first = BottomPreservationMutableHeightRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                bottomPreservationRow("second", height: 80),
                bottomPreservationRow("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let scrollView = try XCTUnwrap(container.descendants(of: NSScrollView.self).first)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 20))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let anchor = try XCTUnwrap(container.captureVisibleAnchor())

        first.height = 130
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: true)

        let restoredFrame = try XCTUnwrap(container.rowFrame(for: anchor.rowID))
        XCTAssertEqual(container.scrollOffsetY, restoredFrame.minY + anchor.offsetWithinRow, accuracy: 0.5)
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight - 1)
    }

    func testStreamingRowRevealKeepsBottomAnchored() {
        let container = bottomPreservationContainer(height: 120)
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(container)
        container.layoutSubtreeIfNeeded()
        let streamingRow = AppKitTranscriptStreamingBubbleView()
        streamingRow.onHeightInvalidated = {
            container.rowHeightInvalidated(
                rowID: AppKitTranscriptTransientRows.streamingRowID,
                preserveBottomIfFollowing: true,
                forceBottomIfPreserving: true,
                animatesLayoutChanges: false
            )
        }
        streamingRow.configure(.init(text: "Short", bubbleMaxWidth: 220))
        container.configure(
            rows: [
                bottomPreservationRow("first", height: 80),
                bottomPreservationRow("second", height: 80),
                AppKitTranscriptLayoutRow(id: AppKitTranscriptTransientRows.streamingRowID, view: streamingRow)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()

        let longText = "Short " + String(repeating: "Streaming content wraps ", count: 18)
        streamingRow.configure(.init(text: longText, bubbleMaxWidth: 220))
        for _ in 0..<80 where streamingRow.displayedTextForTesting != longText {
            streamingRow.advanceStreamingRevealForTesting()
            container.layoutSubtreeIfNeeded()
            XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        }

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    private func bottomPreservationContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func bottomPreservationRow(_ id: String, height: CGFloat) -> AppKitTranscriptLayoutRow {
        AppKitTranscriptLayoutRow(id: id, view: BottomPreservationFixedHeightRowView(height: height))
    }
}

private final class BottomPreservationFixedHeightRowView: NSView {
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

private final class BottomPreservationMutableHeightRowView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

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
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
