@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptScrollBridgeTests: XCTestCase {
    func testCoordinatorBuildsChatItemsIntoContainerRows() {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: [
                .assistantMessage(id: "assistant", text: "Hello"),
                .centeredNote(id: "note", kind: .enteredPlanMode)
            ],
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )

        XCTAssertNotNil(container.rowFrame(for: "assistant"))
        XCTAssertNotNil(container.rowFrame(for: "note"))
    }

    func testScrollRequestPinsContainerToBottom() {
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
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight)

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: false,
            scrollToBottomRequest: 1
        )

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testInitialNonzeroScrollRequestPinsContainerToBottom() {
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

        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testRowHeightInvalidationRelayoutsContainerAndCallsUpstream() {
        let container = makeContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        var invalidationCount = 0

        coordinator.update(
            container: container,
            items: [.assistantMessage(id: "assistant", text: "Short")],
            rowConfiguration: .init(onHeightInvalidated: {
                invalidationCount += 1
            }),
            isFollowing: true,
            scrollToBottomRequest: 0
        )

        let initialHeight = container.documentHeight
        coordinator.update(
            container: container,
            items: [.assistantMessage(id: "assistant", text: String(repeating: "Wrapping text ", count: 80))],
            rowConfiguration: .init(bubbleMaxWidth: 160, onHeightInvalidated: {
                invalidationCount += 1
            }),
            isFollowing: true,
            scrollToBottomRequest: 0
        )

        XCTAssertGreaterThan(container.documentHeight, initialHeight)
        XCTAssertGreaterThan(invalidationCount, 0)
    }

    func testTypographyChangeRemeasuresCachedRows() {
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

        XCTAssertNotEqual(container.documentHeight, smallHeight, accuracy: 0.5)
    }

    func testCoordinatorBuildsTransientRowsIntoContainer() {
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

        XCTAssertNotNil(container.rowFrame(for: "assistant"))
        XCTAssertNotNil(container.rowFrame(for: AppKitTranscriptTransientRows.streamingRowID))
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
