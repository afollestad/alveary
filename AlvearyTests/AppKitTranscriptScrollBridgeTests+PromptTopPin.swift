@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testRowTopScrollRequestPinsPromptRowTop() async throws {
        let container = promptTopPinContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let prompt = promptTopPinPromptItem(rowID: "prompt")
        let items = promptTopPinTallAssistantItems + [prompt] + promptTopPinTrailingAssistantItems
        var metrics: [ChatTranscriptScrollMetrics] = []

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 1
        )
        await container.waitForPromptTopPinRow(id: "prompt")
        let bottomPromptFrame = try XCTUnwrap(container.rowFrame(for: "prompt"))
        await container.waitUntilPromptTopPinAtBottom()
        XCTAssertGreaterThan(container.scrollOffsetY, bottomPromptFrame.minY)

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 2,
            scrollToRowTopRequest: .init(id: 1, rowID: "prompt", topInset: 0),
            onScrollMetricsChanged: { metrics.append($0) }
        )
        for _ in 0..<100 where metrics.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let promptFrame = try XCTUnwrap(container.rowFrame(for: "prompt"))

        XCTAssertEqual(container.scrollOffsetY, promptFrame.minY, accuracy: 0.5)
        XCTAssertFalse(metrics.contains { abs($0.offsetY - promptFrame.minY) > 0.5 })
    }

    func testTransientThinkingRowDoesNotOverridePromptTopPin() async throws {
        let container = promptTopPinContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let prompt = promptTopPinPromptItem(rowID: "prompt")
        let items = promptTopPinTallAssistantItems + [prompt] + promptTopPinTrailingAssistantItems

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 1
        )
        await container.waitForPromptTopPinRow(id: "prompt")
        await container.waitUntilPromptTopPinAtBottom()

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 1,
            scrollToRowTopRequest: .init(id: 1, rowID: "prompt", topInset: 0)
        )
        await container.waitForPromptTopPinOffset(rowID: "prompt")
        let promptFrame = try XCTUnwrap(container.rowFrame(for: "prompt"))
        XCTAssertEqual(container.scrollOffsetY, promptFrame.minY, accuracy: 0.5)

        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(isTurnActive: true, isThinkingAnimated: false),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 1,
            scrollToRowTopRequest: .init(id: 1, rowID: "prompt", topInset: 0)
        )
        await container.waitForPromptTopPinRow(id: AppKitTranscriptTransientRows.thinkingRowID)

        XCTAssertEqual(container.scrollOffsetY, promptFrame.minY, accuracy: 0.5)
    }
}

private extension AppKitTranscriptScrollBridgeTests {
    func promptTopPinContainer() -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        container.layoutSubtreeIfNeeded()
        return container
    }

    var promptTopPinTallAssistantItems: [ChatItem] {
        (0..<6).map { index in
            .assistantMessage(id: "assistant-\(index)", text: String(repeating: "Line \(index) ", count: 40))
        }
    }

    var promptTopPinTrailingAssistantItems: [ChatItem] {
        [
            .assistantMessage(id: "assistant-after-prompt", text: String(repeating: "After prompt ", count: 80))
        ]
    }

    func promptTopPinPromptItem(rowID: String) -> ChatItem {
        .promptBlock(
            id: rowID,
            prompt: PromptEntry(
                id: rowID,
                questions: [
                    .init(
                        question: "Choose a direction",
                        header: "Plan",
                        options: [
                            .init(label: "Proceed", description: "Continue with the plan."),
                            .init(label: "Revise", description: "Adjust the plan first.")
                        ],
                        multiSelect: false
                    )
                ],
                submittedSummary: nil
            )
        )
    }
}

private extension AppKitTranscriptScrollContainerView {
    func waitForPromptTopPinRow(id: String) async {
        for _ in 0..<100 where rowFrame(for: id) == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitUntilPromptTopPinAtBottom() async {
        for _ in 0..<100 where abs(visibleBottomY - documentHeight) > 0.5 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitForPromptTopPinOffset(rowID: String) async {
        for _ in 0..<100 {
            guard let frame = rowFrame(for: rowID),
                  abs(scrollOffsetY - frame.minY) <= 0.5 else {
                try? await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            return
        }
    }
}
