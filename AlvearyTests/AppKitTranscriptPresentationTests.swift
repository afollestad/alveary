import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptPresentationTests: XCTestCase {
    func testFollowAndScrollOnlyUpdatesReuseGroupingAndAliases() {
        let cache = AppKitTranscriptPresentationCache()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        container.layoutSubtreeIfNeeded()
        let items: [ChatItem] = [
            .standaloneTool(id: "first", tool: tool(id: "first-tool")),
            .standaloneTool(id: "second", tool: tool(id: "second-tool"))
        ]

        for (request, isFollowing) in [true, false, true].enumerated() {
            let presentation = cache.presentation(for: items)
            let expandedIDs = presentation.migratedExpandedRowIDs([]).intersection(presentation.expandableRowIDs)
            coordinator.update(
                container: container,
                items: presentation.items,
                presentation: presentation,
                rowConfiguration: .init(expandedRowIDs: expandedIDs),
                isFollowing: isFollowing,
                scrollToBottomRequest: request
            )
        }

        XCTAssertEqual(cache.preparationCount, 1)
        XCTAssertNotNil(container.rowFrame(for: "activity-first"))
        XCTAssertEqual(container.rowFrame(for: "first"), container.rowFrame(for: "activity-first"))
        XCTAssertEqual(container.rowFrame(for: "second"), container.rowFrame(for: "activity-first"))
    }

    func testPromptSubmissionWithUnchangedIDsUpdatesExpansionWithoutMutatingPriorPresentation() throws {
        let cache = AppKitTranscriptPresentationCache()
        let first: [ChatItem] = [
            .standaloneTool(id: "tool", tool: tool(id: "tool")),
            .promptBlock(id: "prompt", prompt: .init(id: "question", questions: [], submittedSummary: nil))
        ]
        let second: [ChatItem] = [
            first[0],
            .promptBlock(id: "prompt", prompt: .init(id: "question", questions: [], submittedSummary: "Q: Continue?\nA: Yes"))
        ]
        let initial = cache.presentation(for: first)
        let updated = cache.presentation(for: second)

        XCTAssertEqual(cache.preparationCount, 2)
        XCTAssertFalse(initial.expandableRowIDs.contains("prompt"))
        XCTAssertTrue(updated.expandableRowIDs.contains("prompt"))
        XCTAssertEqual(updated.migratedExpandedRowIDs(["prompt"]), ["activity-tool", "prompt"])
        guard case .activityGroup(_, let children) = try XCTUnwrap(updated.visualRows.first),
              case .prompt(_, _, let prompt) = try XCTUnwrap(children.last) else {
            return XCTFail("Expected the submitted prompt in the cached group")
        }
        XCTAssertEqual(prompt.submittedSummary, "Q: Continue?\nA: Yes")
        XCTAssertEqual(initial.items, first)
    }

    func testToolPreviewReplacementWithUnchangedIDsUpdatesActivityBoundaries() {
        let cache = AppKitTranscriptPresentationCache()
        let prompt = ChatItem.promptBlock(id: "prompt", prompt: .init(id: "question", questions: [], submittedSummary: nil))
        let initial = cache.presentation(for: [.standaloneTool(id: "edit", tool: tool(id: "edit-tool")), prompt])
        let preview = ToolContentPreview(content: "# Plan", language: "markdown", baseURL: nil, origin: .exitPlanModeFollowUp)
        let updated = cache.presentation(for: [
            .standaloneTool(id: "edit", tool: tool(id: "edit-tool", preview: preview)), prompt
        ])

        XCTAssertEqual(cache.preparationCount, 2)
        XCTAssertEqual(initial.visualRows.map(\.id), ["activity-edit"])
        XCTAssertEqual(updated.visualRows.map(\.id), ["edit", "prompt"])
        XCTAssertTrue(updated.rowIDAliases.isEmpty)
    }

    func testRawAndGeneratedIDCollisionsKeepAliasesAligned() {
        let items: [ChatItem] = [
            .toolGroup(id: "row", tools: [tool(id: "first"), tool(id: "second")]),
            .assistantMessage(id: "activity-row", text: "First reserved id"),
            .assistantMessage(id: "activity-2-row", text: "Second reserved id"),
            .toolGroup(id: "3-row", tools: [tool(id: "third"), tool(id: "fourth")])
        ]
        let presentation = AppKitTranscriptPresentation(items: items)

        XCTAssertEqual(presentation.visualRows.map(\.id), [
            "activity-3-row", "activity-row", "activity-2-row", "activity-2-3-row"
        ])
        XCTAssertEqual(presentation.rowIDAliases, ["row": "activity-3-row", "3-row": "activity-2-3-row"])
        XCTAssertEqual(presentation.migratedExpandedRowIDs(["row", "3-row"]), ["activity-3-row", "activity-2-3-row"])
    }

    private func tool(id: String, preview: ToolContentPreview? = nil) -> ToolEntry {
        ToolEntry(
            id: id, name: "Edit", summary: "Edited file", input: "{}", output: nil, stderr: nil,
            isComplete: true, isInterrupted: false, isImage: false, noOutputExpected: false, isError: false,
            previewOverride: preview
        )
    }
}
