@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testTransientOnlyUpdateReusesPersistedRows() async throws {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        container.layoutSubtreeIfNeeded()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<6).map { index in
            ChatItem.assistantMessage(id: "assistant-\(index)", text: "Message \(index)")
        }

        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(streamingText: "Short"),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        for _ in 0..<100 where container.rowFrame(for: AppKitTranscriptTransientRows.streamingRowID) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let buildsAfterInstall = coordinator.persistedRowBuildCountForTesting
        let persistedRowView = try XCTUnwrap(container.transcriptDocumentView.subviews.first { $0.identifier?.rawValue == "assistant-0" })

        coordinator.update(
            container: container,
            items: items,
            transientRows: .init(streamingText: "Short and then longer"),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 0
        )

        XCTAssertEqual(coordinator.persistedRowBuildCountForTesting, buildsAfterInstall)
        let streamingRow = try XCTUnwrap(
            container.transcriptDocumentView.subviews.first { $0.identifier?.rawValue == AppKitTranscriptTransientRows.streamingRowID }
                as? AppKitTranscriptStreamingBubbleView
        )
        XCTAssertEqual(streamingRow.displayedTextForTesting, "Short and then longer")
        XCTAssertIdentical(container.transcriptDocumentView.subviews.first { $0.identifier?.rawValue == "assistant-0" }, persistedRowView)

        coordinator.update(
            container: container,
            items: items + [.assistantMessage(id: "assistant-6", text: "Message 6")],
            transientRows: .init(),
            rowConfiguration: .init(bubbleMaxWidth: 220),
            isFollowing: true,
            scrollToBottomRequest: 0
        )
        for _ in 0..<100 where container.rowFrame(for: "assistant-6") == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(coordinator.persistedRowBuildCountForTesting, buildsAfterInstall + 1)
        XCTAssertNil(container.rowFrame(for: AppKitTranscriptTransientRows.streamingRowID))
    }
}
