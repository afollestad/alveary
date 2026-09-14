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

        waitForAnimatedHeightSettle(container)

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
        waitForAnimatedHeightSettle(container)

        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
    }

    func testDeferredHeightInvalidationsMeasureDistinctRowsInOneBatch() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "This regression requires deferred frame animation.")
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 80)
        let second = AnimatedCountingHeightRowView()
        let third = AnimatedCountingHeightRowView()
        let unchanged = AnimatedCountingHeightRowView()
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second),
                AppKitTranscriptLayoutRow(id: "third", view: third),
                AppKitTranscriptLayoutRow(id: "unchanged", view: unchanged)
            ],
            preserveBottomIfFollowing: false
        )
        first.height = 200
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)
        second.measurementCount = 0
        third.measurementCount = 0
        unchanged.measurementCount = 0
        let heights: [CGFloat] = [100, 120, 140]
        for height in heights {
            second.height = height
            container.rowHeightInvalidated(rowID: "second", preserveBottomIfFollowing: false)
        }
        third.height = 160
        container.rowHeightInvalidated(rowID: "third", preserveBottomIfFollowing: false)

        var observedBatch = false
        container.transcriptDocumentView.runAfterActiveFrameAnimation {
            observedBatch = true
            XCTAssertEqual(container.rowFrame(for: "second")?.height, 140)
            XCTAssertEqual(container.rowFrame(for: "third")?.height, 160)
            XCTAssertEqual(second.measurementCount, 1)
            XCTAssertEqual(third.measurementCount, 1)
            XCTAssertEqual(unchanged.measurementCount, 0)
        }
        waitForAnimatedHeightSettle(container) { observedBatch }

        XCTAssertTrue(observedBatch)
        XCTAssertNil(container.pendingHeightInvalidation)
    }

    func testDeferredUnknownRowPreservesFullInvalidationAndStreamingFollowIntent() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "This regression requires deferred frame animation.")
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 80)
        let second = AnimatedCountingHeightRowView()
        let third = AnimatedCountingHeightRowView()
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "first", view: first),
                AppKitTranscriptLayoutRow(id: "second", view: second),
                AppKitTranscriptLayoutRow(id: "third", view: third)
            ],
            preserveBottomIfFollowing: true
        )
        container.scrollToBottom()
        first.height = 200
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: true)
        second.measurementCount = 0
        third.measurementCount = 0
        second.height = 140
        container.rowHeightInvalidated(rowID: "second", preserveBottomIfFollowing: false)
        third.height = 160
        container.rowHeightInvalidated(
            preserveBottomIfFollowing: true, forceBottomIfPreserving: true, animatesLayoutChanges: false
        )

        var observedBatch = false
        container.transcriptDocumentView.runAfterActiveFrameAnimation {
            observedBatch = true
            XCTAssertEqual(container.rowFrame(for: "second")?.height, 140)
            XCTAssertEqual(container.rowFrame(for: "third")?.height, 160)
            XCTAssertEqual(second.measurementCount, 1)
            XCTAssertEqual(third.measurementCount, 1)
            XCTAssertFalse(container.transcriptDocumentView.hasActiveFrameAnimation)
            XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        }
        waitForAnimatedHeightSettle(container) { observedBatch }

        XCTAssertTrue(observedBatch)
    }

    func testDeferredStreamingAfterCollapseCancelsStaleScrollCompletion() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "This regression requires deferred frame animation.")
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 200)
        let streaming = AnimatedHeightMutableRowView(height: 80)
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "first", view: first), AppKitTranscriptLayoutRow(id: "streaming", view: streaming)],
            preserveBottomIfFollowing: true
        )
        container.scrollToBottom()
        let finalDocumentHeight = container.documentHeight - 60
        first.height = 80
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: true)
        XCTAssertNotNil(container.activeScrollAnimationToken)
        streaming.height = 140
        container.rowHeightInvalidated(
            rowID: "streaming", preserveBottomIfFollowing: true, forceBottomIfPreserving: true, animatesLayoutChanges: false
        )
        var observedBatch = false
        container.transcriptDocumentView.runAfterActiveFrameAnimation {
            observedBatch = true
            XCTAssertNil(container.activeScrollAnimationToken)
            XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
        }
        waitForAnimatedHeightSettle(container) { observedBatch && container.activeScrollAnimationToken == nil }

        XCTAssertTrue(observedBatch)
        XCTAssertEqual(container.documentHeight, finalDocumentHeight, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testResizeDuringCollapseCommitsLatestWidthAfterAnimation() throws {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 200)
        let wrapping = AnimatedWidthSensitiveRowView()
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "first", view: first), AppKitTranscriptLayoutRow(id: "wrapping", view: wrapping)],
            preserveBottomIfFollowing: true
        )
        container.scrollToBottom()
        first.height = 80
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: true)

        container.frame.size.width = 180
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.frame.size.width = 240
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        waitForAnimatedHeightSettle(container) { container.activeScrollAnimationToken == nil }

        let wrappingFrame = try XCTUnwrap(container.rowFrame(for: "wrapping"))
        XCTAssertEqual(container.transcriptDocumentView.frame.width, 240, accuracy: 0.5)
        XCTAssertEqual(wrappingFrame.width, 240 - transcriptScrollLeadingInset - transcriptScrollTrailingInset, accuracy: 0.5)
        XCTAssertEqual(wrappingFrame.height, ceil(24_000 / wrappingFrame.width), accuracy: 0.5)
        XCTAssertEqual(container.documentHeight, wrappingFrame.maxY + 14, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testReplacementDuringAnimationInstallsOnlyLatestRows() throws {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 200)
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "first", view: first), animatedHeightRow("old", height: 80)],
            preserveBottomIfFollowing: false
        )
        first.height = 80
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: false)

        container.configure(rows: [animatedHeightRow("superseded", height: 300)], preserveBottomIfFollowing: false)
        container.configure(rows: [animatedHeightRow("latest", height: 60)], preserveBottomIfFollowing: false)
        waitForAnimatedHeightSettle(container) { container.rowFrame(for: "latest") != nil }

        XCTAssertNil(container.rowFrame(for: "old"))
        XCTAssertNil(container.rowFrame(for: "superseded"))
        let latestFrame = try XCTUnwrap(container.rowFrame(for: "latest"))
        XCTAssertEqual(latestFrame.height, 60, accuracy: 0.5)
        XCTAssertEqual(container.documentHeight, latestFrame.maxY + 14, accuracy: 0.5)
        XCTAssertEqual(container.scrollOffsetY, 0, accuracy: 0.5)
    }

    func testDeferredStreamingGrowthHonorsFollowingCancellation() {
        let container = makeAnimatedHeightContainer(height: 120)
        let first = AnimatedHeightMutableRowView(height: 80)
        let streaming = AnimatedHeightMutableRowView(height: 80)
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "first", view: first), AppKitTranscriptLayoutRow(id: "streaming", view: streaming)],
            preserveBottomIfFollowing: true
        )
        container.scrollToBottom()
        first.height = 200
        container.rowHeightInvalidated(rowID: "first", preserveBottomIfFollowing: true)
        streaming.height = 140
        container.rowHeightInvalidated(
            rowID: "streaming", preserveBottomIfFollowing: true, forceBottomIfPreserving: true, animatesLayoutChanges: false
        )

        container.scrollContentView(toY: 20)
        container.preservesBottomOnResize = false
        waitForAnimatedHeightSettle(container)

        XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight - 1)
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

        waitForAnimatedHeightSettle(container) {
            !clipView.isAnimatingVisibleHeight
        }

        XCTAssertFalse(container.transcriptDocumentView.hasActiveFrameAnimation)
        XCTAssertFalse(clipView.isAnimatingVisibleHeight)
        XCTAssertEqual(clipView.visibleHeightForTesting, block.intrinsicContentSize.height, accuracy: 0.5)
    }

    func testRemovedThoughtRowAnimatesOutWhenMotionIsAllowed() {
        let container = makeAnimatedHeightContainer(height: 120)
        let thoughtView = AnimatedHeightFixedRowView(height: 30)
        let belowView = AnimatedHeightFixedRowView(height: 40)
        let thoughtID = AppKitTranscriptTransientRows.thoughtRowID(sequence: 3)
        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: thoughtID, view: thoughtView),
                AppKitTranscriptLayoutRow(id: "below", view: belowView)
            ],
            preserveBottomIfFollowing: false
        )

        container.configure(
            rows: [
                AppKitTranscriptLayoutRow(id: "below", view: belowView)
            ],
            preserveBottomIfFollowing: false
        )

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertNil(thoughtView.superview)
            return
        }

        XCTAssertTrue(thoughtView.superview === container.transcriptDocumentView)
        XCTAssertEqual(thoughtView.identifier?.rawValue, thoughtID)
        XCTAssertTrue(container.transcriptDocumentView.hasActiveFrameAnimation)

        let deadline = Date(timeIntervalSinceNow: 0.6)
        while (thoughtView.superview != nil || container.transcriptDocumentView.hasActiveFrameAnimation) && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertNil(thoughtView.superview)
        XCTAssertFalse(container.transcriptDocumentView.hasActiveFrameAnimation)
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

    private func waitForAnimatedHeightSettle(
        _ container: AppKitTranscriptScrollContainerView,
        until extraCondition: () -> Bool = { true }
    ) {
        let deadline = Date(timeIntervalSinceNow: appExpansionAnimationDuration + 2)
        while Date() < deadline &&
            (container.transcriptDocumentView.hasActiveFrameAnimation || !extraCondition()) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
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

private final class AnimatedWidthSensitiveRowView: NSView {
    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: ceil(24_000 / max(bounds.width, 1)))
    }
}

private final class AnimatedCountingHeightRowView: NSView {
    var height: CGFloat = 80
    var measurementCount = 0

    override var fittingSize: NSSize {
        measurementCount += 1
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
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
