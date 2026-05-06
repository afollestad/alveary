@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
private var retainedAnimatedHeightWindows: [NSWindow] = []

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testAnimatedHeightCollapseDoesNotApplyFinalDocumentSizeDuringAnimation() {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 200)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                animatedHeightRow("second", height: 80),
                animatedHeightRow("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let initialDocumentHeight = container.documentHeight
        let initialScrollOffsetY = container.scrollOffsetY
        let finalDocumentHeight = initialDocumentHeight - 120
        let finalScrollOffsetY = initialScrollOffsetY - 120

        first.height = 80
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)

        XCTAssertEqual(container.documentHeight, initialDocumentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, initialScrollOffsetY, accuracy: 0.5)

        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.documentHeight, initialDocumentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, initialScrollOffsetY, accuracy: 0.5)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: appExpansionAnimationDuration + 0.1))

        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, finalScrollOffsetY, accuracy: 0.5)
    }

    func testAnimatedHeightExpansionAppliesFinalDocumentSizeImmediately() {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 80)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                animatedHeightRow("second", height: 80),
                animatedHeightRow("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let finalDocumentHeight = container.documentHeight + 120

        first.height = 200
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)

        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
    }

    func testAnimatedHeightExpansionAtBottomDoesNotForceScrollToNewBottom() {
        let container = makeAnimatedHeightContainer(height: 120)
        let third = AnimatedHeightMutableRowView(height: 80)
        container.configure(
            rows: [
                animatedHeightRow("first", height: 80),
                animatedHeightRow("second", height: 80),
                AppKitTranscriptLayoutRow(id: "third", view: third)
            ],
            preserveBottomIfFollowing: false
        )
        container.scrollToBottom()
        let initialScrollOffsetY = container.scrollOffsetY
        let finalDocumentHeight = container.documentHeight + 120

        third.height = 200
        container.rowHeightInvalidated(rowID: "third", preserveBottomIfFollowing: true)

        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, initialScrollOffsetY, accuracy: 0.5)
    }

    func testHeightInvalidationDuringActiveFrameAnimationIsDeferred() {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 200)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                animatedHeightRow("second", height: 80),
                animatedHeightRow("third", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        let finalDocumentHeight = container.documentHeight - 60

        first.height = 80
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)
        first.height = 140
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: appExpansionAnimationDuration + 0.1))

        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
    }

    private func makeAnimatedHeightContainer(height: CGFloat) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        container.layoutSubtreeIfNeeded()
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        retainedAnimatedHeightWindows.append(window)
        window.contentView?.addSubview(container)
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func animatedHeightRow(_ id: String, height: CGFloat) -> AppKitTranscriptLayoutRow {
        AppKitTranscriptLayoutRow(id: id, view: AnimatedHeightFixedRowView(height: height))
    }
}

private final class AnimatedHeightFixedRowView: NSView {
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

private final class AnimatedHeightMutableRowView: NSView {
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
