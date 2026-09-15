@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollContainerTests {
    func testCollapsedToolDetailsPrewarmOnlyNearViewport() async throws {
        let container = prewarmingContainer()
        let rows = (0..<40).map { makePrewarmingToolRow(id: "tool-\($0)") }
        container.configure(
            rows: rows.enumerated().map { AppKitTranscriptLayoutRow(id: "row-\($0.offset)", view: $0.element) },
            preserveBottomIfFollowing: false
        )
        let first = try XCTUnwrap(rows.first)
        let last = try XCTUnwrap(rows.last)
        XCTAssertNil(first.prewarmedDetailsToolForTesting)

        await waitForViewportPrewarming(container)

        XCTAssertNotNil(first.prewarmedDetailsToolForTesting)
        XCTAssertNil(last.prewarmedDetailsToolForTesting)
        let documentHeight = container.documentHeight

        container.scrollToBottom()
        await waitForViewportPrewarming(container)

        XCTAssertNotNil(last.prewarmedDetailsToolForTesting)
        XCTAssertEqual(container.documentHeight, documentHeight, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testRemovedToolDoesNotRunQueuedPrewarm() async {
        let container = prewarmingContainer()
        let row = makePrewarmingToolRow(id: "removed")
        container.configure(rows: [AppKitTranscriptLayoutRow(id: "removed", view: row)], preserveBottomIfFollowing: false)

        container.configure(rows: [], preserveBottomIfFollowing: false)
        await waitForViewportPrewarming(container)

        XCTAssertNil(row.prewarmedDetailsToolForTesting)
        XCTAssertNil(row.superview)
    }

    func testQueuedPrewarmDropsRowsOutsideUpdatedMargin() async {
        let container = prewarmingContainer()
        let rows = (0..<40).map { makePrewarmingToolRow(id: "tool-\($0)") }
        container.configure(
            rows: rows.enumerated().map { AppKitTranscriptLayoutRow(id: "row-\($0.offset)", view: $0.element) },
            preserveBottomIfFollowing: false
        )

        container.scrollToBottom()
        await waitForViewportPrewarming(container)

        XCTAssertNil(rows[0].prewarmedDetailsToolForTesting)
        XCTAssertNotNil(rows[39].prewarmedDetailsToolForTesting)
    }

    func testDetachedContainerDoesNotRestartPrewarmingFromLateInvalidation() async {
        let container = prewarmingContainer()
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(container)
        let row = makePrewarmingToolRow(id: "detached")
        container.configure(rows: [AppKitTranscriptLayoutRow(id: "detached", view: row)], preserveBottomIfFollowing: false)

        container.removeFromSuperview()
        container.rowHeightInvalidated(rowID: "detached", preserveBottomIfFollowing: false, animatesLayoutChanges: false)
        await waitForViewportPrewarming(container)

        XCTAssertTrue(container.hasMountedWindow)
        XCTAssertNil(row.prewarmedDetailsToolForTesting)
        XCTAssertNotNil(window.contentView)
    }

    func testExpandedPrewarmableParentStillVisitsCollapsedChildren() async {
        let container = prewarmingContainer()
        let parent = PrewarmedParentView()
        let child = makePrewarmingToolRow(id: "child")
        child.frame = CGRect(x: 0, y: 0, width: 260, height: 30)
        parent.addSubview(child)
        container.configure(rows: [AppKitTranscriptLayoutRow(id: "parent", view: parent)], preserveBottomIfFollowing: false)

        await waitForViewportPrewarming(container)

        XCTAssertNotNil(child.prewarmedDetailsToolForTesting)
    }

    func testViewportUpdatesDoNotRediscoverStableRowSubviews() {
        let container = prewarmingContainer()
        let root = SubviewReadCountingView()
        var views = [root]
        for _ in 0..<40 {
            let child = SubviewReadCountingView(frame: CGRect(x: 0, y: 0, width: 280, height: 40))
            views.last?.addSubview(child)
            views.append(child)
        }
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "deep-row", view: root)],
            preserveBottomIfFollowing: false
        )
        let readsAfterDiscovery = views.map(\.subviewReadCount).reduce(0, +)

        for _ in 0..<10 {
            container.updateViewportPrewarming(in: container.scrollView.contentView.bounds)
        }

        XCTAssertGreaterThan(readsAfterDiscovery, 0)
        XCTAssertEqual(views.map(\.subviewReadCount).reduce(0, +), readsAfterDiscovery)
    }

    func testHeightInvalidationDiscoversNewPrewarmableDescendants() async {
        let container = prewarmingContainer()
        let parent = PrewarmedParentView()
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "parent", view: parent)],
            preserveBottomIfFollowing: false
        )
        let child = PrewarmProbeView(frame: CGRect(x: 0, y: 0, width: 260, height: 30))
        parent.addSubview(child)

        container.rowHeightInvalidated(
            rowID: "parent",
            preserveBottomIfFollowing: false,
            animatesLayoutChanges: false
        )
        await waitForViewportPrewarming(container)

        XCTAssertEqual(child.prewarmCount, 1)
    }

    func testRegisteredCandidateCanNeedPrewarmingAfterAViewportChange() async {
        let container = prewarmingContainer()
        let parent = PrewarmedParentView()
        let child = PrewarmProbeView(frame: CGRect(x: 0, y: 0, width: 260, height: 30))
        child.shouldPrewarm = false
        parent.addSubview(child)
        container.configure(
            rows: [AppKitTranscriptLayoutRow(id: "parent", view: parent)],
            preserveBottomIfFollowing: false
        )
        await waitForViewportPrewarming(container)
        XCTAssertEqual(child.prewarmCount, 0)

        child.shouldPrewarm = true
        container.updateViewportPrewarming(in: container.scrollView.contentView.bounds)
        await waitForViewportPrewarming(container)

        XCTAssertEqual(child.prewarmCount, 1)
    }
}

@MainActor
private func prewarmingContainer() -> AppKitTranscriptScrollContainerView {
    let container = AppKitTranscriptScrollContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
    container.layoutSubtreeIfNeeded()
    return container
}

@MainActor
private func makePrewarmingToolRow(id: String) -> AppKitTranscriptInlineToolRowView {
    let row = AppKitTranscriptInlineToolRowView()
    row.configure(.init(tool: ToolEntry(
        id: id,
        name: "CustomTool",
        summary: "Read `Sources/Example.swift`",
        input: "{}",
        output: "A retained tool result",
        stderr: nil,
        isComplete: true,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )))
    return row
}

@MainActor
private func waitForViewportPrewarming(_ container: AppKitTranscriptScrollContainerView) async {
    for _ in 0..<100 where container.viewportPrewarmTask != nil {
        try? await Task.sleep(for: .milliseconds(1))
    }
    XCTAssertNil(container.viewportPrewarmTask)
}

@MainActor
private final class PrewarmedParentView: NSView, AppKitTranscriptViewportPrewarmable {
    var needsTranscriptViewportPrewarm: Bool { false }
    func prewarmForTranscriptViewport() {}
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 40) }
}

@MainActor
private final class SubviewReadCountingView: NSView {
    private(set) var subviewReadCount = 0

    override var subviews: [NSView] {
        get {
            subviewReadCount += 1
            return super.subviews
        }
        set {
            super.subviews = newValue
        }
    }

    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 40) }
}

@MainActor
private final class PrewarmProbeView: NSView, AppKitTranscriptViewportPrewarmable {
    private(set) var prewarmCount = 0
    var shouldPrewarm = true
    var needsTranscriptViewportPrewarm: Bool { shouldPrewarm && prewarmCount == 0 }
    func prewarmForTranscriptViewport() { prewarmCount += 1 }
}
