@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testExitPlanModeFollowUpMarkdownMutationRendersAssistantPreviewBubble() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: planFollowUpMarkdownEditTool(origin: .exitPlanModeFollowUp)
                )
            ],
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["edit-row-plan-preview"])
        let previewBubble = try XCTUnwrap(rows[0].view as? AppKitTranscriptTextBubbleRowView)
        previewBubble.frame = NSRect(x: 0, y: 0, width: 800, height: 1_000)
        previewBubble.layoutSubtreeIfNeeded()
        XCTAssertEqual(previewBubble.configuration?.role, .assistant)
        XCTAssertEqual(previewBubble.configuration?.markdown, "# Plan\n\n- Existing\n- Follow-up")
    }

    func testCachedExitPlanModeFollowUpMarkdownMutationReplacesToolRowWhenPreviewArrives() throws {
        let factory = AppKitTranscriptRowFactory()
        let initialRows = factory.makeRows(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: planFollowUpMarkdownEditTool(origin: nil)
                )
            ],
            configuration: .init()
        )
        XCTAssertEqual(initialRows.map(\.id), ["edit-row"])
        let row = try XCTUnwrap(initialRows.first?.view as? AppKitTranscriptInlineToolRowView)
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.planFollowUpDescendants(of: AppKitMarkdownView.self).isEmpty)

        let completedRows = factory.makeRows(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: planFollowUpMarkdownEditTool(origin: .exitPlanModeFollowUp)
                )
            ],
            configuration: .init()
        )

        XCTAssertEqual(completedRows.map(\.id), ["edit-row-plan-preview"])

        let previewBubble = try XCTUnwrap(completedRows[0].view as? AppKitTranscriptTextBubbleRowView)
        previewBubble.frame = NSRect(x: 0, y: 0, width: 800, height: 1_000)
        previewBubble.layoutSubtreeIfNeeded()
        XCTAssertEqual(previewBubble.configuration?.role, .assistant)
        XCTAssertEqual(previewBubble.configuration?.markdown, "# Plan\n\n- Existing\n- Follow-up")
    }

    func testGenericMarkdownMutationPreviewDoesNotExpandByDefault() throws {
        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: planFollowUpMarkdownEditTool(origin: .knownMarkdownMutation)
                )
            ],
            configuration: .init()
        )

        XCTAssertEqual(rows.map(\.id), ["edit-row"])
        let row = try XCTUnwrap(rows.first?.view as? AppKitTranscriptInlineToolRowView)
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.planFollowUpDescendants(of: AppKitMarkdownView.self).isEmpty)

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.planFollowUpDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.planFollowUpRenderedText.contains("Follow-up"))
    }

    func testExitPlanModeFollowUpMarkdownMutationPreparesAssistantPreviewBubbleMarkdown() {
        let factory = AppKitTranscriptRowFactory()
        let requests = factory.markdownPreparationRequests(
            for: [
                .standaloneTool(
                    id: "edit-row",
                    tool: planFollowUpMarkdownEditTool(origin: .exitPlanModeFollowUp)
                )
            ],
            configuration: .init()
        )

        XCTAssertEqual(requests.map(\.rowID), ["edit-row-plan-preview"])
        XCTAssertEqual(requests.first?.markdown, "# Plan\n\n- Existing\n- Follow-up")
        XCTAssertEqual(requests.first?.inlineCodeStyle, AppMarkdownInlineCodeStyle.assistantBubble)
        XCTAssertEqual(requests.first?.composerChipMode, AppMarkdownComposerChipMode.none)
    }
}

private func planFollowUpMarkdownEditTool(origin: ToolContentPreviewOrigin?) -> ToolEntry {
    let preview = origin.map {
        ToolContentPreview(
            content: "# Plan\n\n- Existing\n- Follow-up",
            language: "markdown",
            baseURL: nil,
            origin: $0
        )
    }
    return ToolEntry(
        id: "edit-1",
        name: "Edit",
        summary: "Edit `plan.md`",
        input: #"{"file_path":"/tmp/plan.md","old_string":"- Existing","new_string":"- Existing\n- Follow-up"}"#,
        output: "Updated",
        stderr: nil,
        isComplete: true,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false,
        previewOverride: preview
    )
}

private extension NSView {
    var planFollowUpRenderedText: String {
        planFollowUpDescendants(of: NSTextField.self).map(\.stringValue).joined(separator: "\n") + "\n"
            + planFollowUpDescendants(of: AppKitMarkdownTextView.self).map(\.string).joined(separator: "\n")
    }

    func planFollowUpDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.planFollowUpDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
