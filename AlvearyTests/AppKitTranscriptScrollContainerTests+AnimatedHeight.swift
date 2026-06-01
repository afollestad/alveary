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

    func testAnimatedSubAgentExpansionKeepsClipAtCollapsedHeightDuringFrameAnimation() throws {
        let container = makeAnimatedHeightContainer(height: 140)
        let block = AppKitTranscriptSubAgentBlockView()
        block.configure(
            .init(
                agents: [
                    animatedHeightAgent(
                        id: "agent-one",
                        description: "Explore project structure",
                        result: (0..<22).map { "result line \($0)" }.joined(separator: "\n")
                    )
                ]
            )
        )
        block.onHeightInvalidated = { [weak container] in
            container?.rowHeightInvalidated(rowID: "agents", preserveBottomIfFollowing: false)
        }
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "agents", view: block),
                animatedHeightRow("below", height: 80)
            ],
            preserveBottomIfFollowing: false
        )
        let collapsedHeight = try XCTUnwrap(container.rowFrame(for: "agents")?.height)
        let clipView = try XCTUnwrap(block.descendants(of: AppKitTranscriptExpandableClipView.self).first)

        block.setExpanded(true)

        XCTAssertTrue(container.transcriptDocumentView.hasActiveFrameAnimation)
        XCTAssertTrue(clipView.isAnimatingVisibleHeight)
        if let presentationHeight = clipView.layer?.presentation()?.bounds.height {
            XCTAssertLessThanOrEqual(presentationHeight, collapsedHeight + 0.5)
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: appExpansionAnimationDuration + 0.4))

        XCTAssertFalse(container.transcriptDocumentView.hasActiveFrameAnimation)
        XCTAssertFalse(clipView.isAnimatingVisibleHeight)
        XCTAssertEqual(clipView.visibleHeightForTesting, block.intrinsicContentSize.height, accuracy: 0.5)
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

private func animatedHeightAgent(
    id: String,
    description: String,
    result: String
) -> SubAgentEntry {
    SubAgentEntry(
        id: id,
        agentType: "explorer",
        description: description,
        statusDescription: nil,
        lastToolName: nil,
        tools: [],
        result: result,
        isComplete: true,
        toolUseCount: 0
    )
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
