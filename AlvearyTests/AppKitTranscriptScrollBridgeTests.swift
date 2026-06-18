@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptScrollBridgeTests: XCTestCase {
    func testCoordinatorBuildsChatItemsIntoContainerRows() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: [
                .assistantMessage(id: "assistant", text: "Hello"),
                .transcriptNote(id: "note", kind: .enteredPlanMode)
            ],
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: "assistant")

        XCTAssertNotNil(container.rowFrame(for: "assistant"))
        XCTAssertNotNil(container.rowFrame(for: "note"))
    }

    func testCoordinatorKeepsInitialColdMarkdownRowsVisibleWhileDocumentsPrepare() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let rowID = "cold-\(UUID().uuidString)"

        coordinator.update(
            container: container,
            items: [
                .assistantMessage(id: rowID, text: "Cold markdown \(UUID().uuidString) with `code`.")
            ],
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )

        XCTAssertNotNil(container.rowFrame(for: rowID))
    }

    func testCoordinatorDefersSubsequentColdMarkdownRowsUntilDocumentsArePrepared() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let rowID = "cold-\(UUID().uuidString)"

        coordinator.update(
            container: container,
            items: [
                .transcriptNote(id: "note", kind: .enteredPlanMode)
            ],
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: "note")

        coordinator.update(
            container: container,
            items: [
                .assistantMessage(id: rowID, text: "Cold markdown \(UUID().uuidString) with `code`.")
            ],
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )

        XCTAssertNil(container.rowFrame(for: rowID))

        await container.waitForRow(id: rowID)

        XCTAssertNotNil(container.rowFrame(for: rowID))
    }

    func testScrollRequestPinsContainerToBottom() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<8).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        }

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: "assistant-7")
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight)

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 1
        )
        await container.waitForRow(id: "assistant-7")
        await container.waitUntilAtBottom()

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testFollowingOnlyUpdateDoesNotReconfigureContainer() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items: [ChatItem] = [
            .transcriptNote(id: "note", kind: .enteredPlanMode)
        ]
        var metricsCount = 0

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(),
            isFollowing: true,
            scrollToBottomRequest: 0,
            onScrollMetricsChanged: { _ in
                metricsCount += 1
            }
        )
        await container.waitForRow(id: "note")
        try? await Task.sleep(nanoseconds: 20_000_000)
        metricsCount = 0

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0,
            onScrollMetricsChanged: { _ in
                metricsCount += 1
            }
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(metricsCount, 0)
    }

    func testActionContextChangeReconfiguresContainer() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items: [ChatItem] = [
            .transcriptNote(id: "note", kind: .enteredPlanMode)
        ]
        var metricsCount = 0

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(actionContextID: "first"),
            isFollowing: false,
            scrollToBottomRequest: 0,
            onScrollMetricsChanged: { _ in
                metricsCount += 1
            }
        )
        await container.waitForRow(id: "note")
        try? await Task.sleep(nanoseconds: 20_000_000)
        metricsCount = 0

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(actionContextID: "second"),
            isFollowing: false,
            scrollToBottomRequest: 0,
            onScrollMetricsChanged: { _ in
                metricsCount += 1
            }
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertGreaterThan(metricsCount, 0)
    }

    func testInitialNonzeroScrollRequestPinsContainerToBottom() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<8).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        }

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 1
        )
        await container.waitForRow(id: "assistant-7")
        await container.waitUntilAtBottom()

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testRowHeightInvalidationRelayoutsContainer() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: [.assistantMessage(id: "assistant", text: "Short")],
            rowConfiguration: .init(),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: "assistant")

        let initialHeight = container.documentHeight
        coordinator.update(
            container: container,
            items: [.assistantMessage(id: "assistant", text: String(repeating: "Wrapping text ", count: 80))],
            rowConfiguration: .init(bubbleMaxWidth: 160),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        await container.waitForDocumentHeight { $0 > initialHeight }

        XCTAssertGreaterThan(container.documentHeight, initialHeight)
    }

    func testTypographyChangeRemeasuresCachedRows() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items: [ChatItem] = [
            // Keep the fixture below the collapsed-bubble cap so a settings-driven
            // font change must surface as a document-height change.
            .assistantMessage(id: "assistant", text: String(repeating: "settings typography wraps ", count: 4))
        ]
        var smallSettings = AppSettings()
        smallSettings.chatFontSize = 12
        var largeSettings = AppSettings()
        largeSettings.chatFontSize = 24

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(
                bubbleMaxWidth: 220,
                typography: TranscriptTypography(settings: smallSettings)
            ),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: "assistant")
        let smallHeight = container.documentHeight

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(
                bubbleMaxWidth: 220,
                typography: TranscriptTypography(settings: largeSettings)
            ),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForDocumentHeight { abs($0 - smallHeight) > 0.5 }

        XCTAssertNotEqual(container.documentHeight, smallHeight, accuracy: 0.5)
    }

    func testCoordinatorBuildsTransientRowsIntoContainer() async {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: [.assistantMessage(id: "assistant", text: "Hello")],
            transientRows: .init(isTurnActive: true, streamingText: "Streaming"),
            rowConfiguration: .init(),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: AppKitTranscriptTransientRows.streamingRowID)

        XCTAssertNotNil(container.rowFrame(for: "assistant"))
        XCTAssertNotNil(container.rowFrame(for: AppKitTranscriptTransientRows.streamingRowID))
    }

    func testCoordinatorReleasesAfterInstallingStreamingRowCallbacks() async {
        weak var releasedCoordinator: AppKitTranscriptScrollBridgeCoordinator?

        do {
            let container = makeContainer()
            let coordinator = AppKitTranscriptScrollBridgeCoordinator()
            releasedCoordinator = coordinator

            coordinator.update(
                container: container,
                items: [.transcriptNote(id: "note", kind: .enteredPlanMode)],
                transientRows: .init(streamingText: "Streaming"),
                rowConfiguration: .init(),
                isFollowing: true,
                scrollToBottomRequest: 0
            )
            await container.waitForRow(id: AppKitTranscriptTransientRows.streamingRowID)
        }

        for _ in 0..<10 where releasedCoordinator != nil {
            await Task.yield()
        }
        XCTAssertNil(releasedCoordinator)
    }

    func testStreamingHeightInvalidationUsesLatestFollowingState() async throws {
        let container = makeContainer()
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(container)
        container.layoutSubtreeIfNeeded()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<8).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        }
        let longStreamingText = "Short " + String(repeating: "Streaming content wraps ", count: 18)

        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(streamingText: "Short"),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        await container.waitForRow(id: AppKitTranscriptTransientRows.streamingRowID)
        container.scrollToBottom()
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)

        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(streamingText: longStreamingText),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        let streamingRow = try XCTUnwrap(container.rowView(id: AppKitTranscriptTransientRows.streamingRowID) as? AppKitTranscriptStreamingBubbleView)
        container.scrollContentView(toY: max(container.scrollOffsetY - 120, 0))
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight - 1)
        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(streamingText: longStreamingText),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 0
        )

        for _ in 0..<80 where streamingRow.displayedTextForTesting != longStreamingText {
            streamingRow.advanceStreamingRevealForTesting()
            container.layoutSubtreeIfNeeded()
        }

        XCTAssertLessThan(container.visibleBottomY, container.documentHeight - 1)
    }

    func testToolExpansionEchoPreservesScrollOffset() async throws {
        let container = makeContainer()
        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView?.addSubview(container)
        container.layoutSubtreeIfNeeded()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<8).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        } + [
            ChatItem.standaloneTool(id: "tool", tool: bridgeTool())
        ]
        var userHeightChangeCount = 0

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(
                bubbleMaxWidth: 220,
                onUserInitiatedHeightChange: { userHeightChangeCount += 1 }
            ),
            isFollowing: true,
            scrollToBottomRequest: 1
        )
        await container.waitForRow(id: "tool")
        container.scrollToBottom()
        let toolRow = try XCTUnwrap(container.rowView(id: "tool") as? AppKitTranscriptInlineToolRowView)

        toolRow.setExpanded(true)
        let offsetAfterExpansion = container.scrollOffsetY

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(
                bubbleMaxWidth: 220,
                expandedRowIDs: ["tool"],
                onUserInitiatedHeightChange: { userHeightChangeCount += 1 }
            ),
            isFollowing: true,
            scrollToBottomRequest: 1
        )

        XCTAssertEqual(userHeightChangeCount, 1)
        XCTAssertEqual(container.scrollOffsetY, offsetAfterExpansion, accuracy: 0.5)
    }

    func testCoordinatorForwardsScrollMetrics() async throws {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<8).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        }
        var metrics: [ChatTranscriptScrollMetrics] = []
        let metricsExpectation = expectation(description: "Scroll metrics forwarded")
        var didFulfillMetricsExpectation = false

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 1,
            onScrollMetricsChanged: {
                metrics.append($0)
                if $0.isAtBottom && !didFulfillMetricsExpectation {
                    didFulfillMetricsExpectation = true
                    metricsExpectation.fulfill()
                }
            }
        )

        await fulfillment(of: [metricsExpectation], timeout: 1)
        let lastMetrics = try XCTUnwrap(metrics.last)
        XCTAssertEqual(lastMetrics.offsetY, container.scrollOffsetY, accuracy: 0.5)
        XCTAssertEqual(lastMetrics.contentHeight, container.documentHeight, accuracy: 0.5)
        XCTAssertTrue(lastMetrics.isAtBottom)
    }

    private func makeContainer() -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        container.layoutSubtreeIfNeeded()
        return container
    }
}

private extension AppKitTranscriptScrollContainerView {
    func waitForRow(id: String) async {
        for _ in 0..<100 where rowFrame(for: id) == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitUntilAtBottom() async {
        await waitForDocumentHeight { _ in
            abs(visibleBottomY - documentHeight) <= 0.5
        }
    }

    func waitForDocumentHeight(_ predicate: (CGFloat) -> Bool) async {
        for _ in 0..<100 where !predicate(documentHeight) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func rowView(id: String) -> NSView? {
        transcriptDocumentView.subviews.first {
            $0.identifier?.rawValue == id
        }
    }
}

private func bridgeTool(id: String = "tool-use", name: String = "Bash", summary: String = "Running `swift test`") -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: #"{"command":"swift test"}"#,
        output: (1...20).map { "line \($0)" }.joined(separator: "\n"),
        stderr: nil,
        isComplete: true,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}
