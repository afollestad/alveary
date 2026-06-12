@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testGroupedActivityAliasesRawRowIDsToAggregateRowFrame() async throws {
        let container = makeActivityGroupingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: activityGroupingItems,
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForActivityGroupingRow(id: "activity-read-row")

        let groupFrame = try XCTUnwrap(container.rowFrame(for: "activity-read-row"))
        XCTAssertEqual(container.rowFrame(for: "read-row"), groupFrame)
        XCTAssertEqual(container.rowFrame(for: "edit-row"), groupFrame)
    }

    func testGroupedActivityReusesRawRowIDAliasesAcrossUpdates() async throws {
        let container = makeActivityGroupingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()

        coordinator.update(
            container: container,
            items: activityGroupingItems,
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForActivityGroupingRow(id: "activity-read-row")
        let initialFrame = try XCTUnwrap(container.rowFrame(for: "read-row"))

        coordinator.update(
            container: container,
            items: activityGroupingItems,
            rowConfiguration: .init(expandedRowIDs: ["activity-read-row"]),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        await container.waitForActivityGroupingDocumentHeight { $0 > initialFrame.height + 1 }

        XCTAssertNotNil(container.rowFrame(for: "read-row"))
        XCTAssertNotEqual(container.rowFrame(for: "read-row"), initialFrame)
    }

    private var activityGroupingItems: [ChatItem] {
        [
            .standaloneTool(id: "read-row", tool: activityGroupingTool(id: "read-tool", name: "Read", summary: "Read `AGENTS.md`")),
            .standaloneTool(id: "edit-row", tool: activityGroupingTool(id: "edit-tool", name: "Edit", summary: "Edit `Sources/Foo.swift`"))
        ]
    }

    private func makeActivityGroupingContainer() -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func activityGroupingTool(id: String, name: String, summary: String) -> ToolEntry {
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
}

private extension AppKitTranscriptScrollContainerView {
    func waitForActivityGroupingRow(id: String) async {
        for _ in 0..<100 where rowFrame(for: id) == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitForActivityGroupingDocumentHeight(_ predicate: (CGFloat) -> Bool) async {
        for _ in 0..<100 where !predicate(documentHeight) {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
