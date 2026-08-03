import AppKit
import XCTest

@testable import Alveary

/// Drives the real row-factory view tree, because the Edit action has to survive every
/// hop from the factory down to the tool's expanded detail.
@MainActor
final class ScheduledTaskListToolRowTests: XCTestCase {
    func testEditActionReachesTheHandlerFromAGroupedToolRow() throws {
        let editedIDs = try editedDefinitionIDs(for: listToolItem(id: "group"))
        XCTAssertEqual(editedIDs, ["task-1"])
    }

    func testEditActionReachesTheHandlerFromAStandaloneToolRow() throws {
        let item = ChatItem.standaloneTool(id: "tool-standalone", tool: listTool)
        XCTAssertEqual(try editedDefinitionIDs(for: item), ["task-1"])
    }

    private func editedDefinitionIDs(for item: ChatItem) throws -> [String] {
        var edited: [String] = []
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640
        configuration.expandedRowIDs = [item.id]
        configuration.scheduledTaskListActions = ScheduledTaskListToolActions(
            rows: {
                [
                    ScheduledTaskListRow(
                        id: "task-1",
                        title: "Nightly audit",
                        state: .active,
                        scheduleSummary: "Daily at 2:00 AM"
                    )
                ]
            },
            onEdit: { edited.append($0) }
        )

        let factory = AppKitTranscriptRowFactory()
        let rows = factory.makeRows(for: [item], configuration: configuration)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        for row in rows {
            row.view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
            host.addSubview(row.view)
        }
        host.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(
            editButton(in: host),
            "Expected an Edit button in the expanded scheduled-task list"
        )
        _ = button.target?.perform(button.action, with: button)
        return edited
    }

    private func editButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == "Edit" {
            return button
        }
        for subview in view.subviews {
            if let button = editButton(in: subview) {
                return button
            }
        }
        return nil
    }

    private func listToolItem(id: String) -> ChatItem {
        .toolGroup(id: id, tools: [listTool])
    }

    private var listTool: ToolEntry {
        ToolEntry(
            id: "tool-list",
            name: ScheduledTaskHostToolCatalog.listToolName,
            summary: "List scheduled tasks",
            input: "{}",
            output: "Found 1 scheduled task.",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )
    }
}
