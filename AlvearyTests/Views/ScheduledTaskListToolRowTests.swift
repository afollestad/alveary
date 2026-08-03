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

    /// Nothing scheduled still has to answer the question the row asked; the detail rendering
    /// live definitions means an empty list would otherwise expand to blank space.
    func testEmptyListShowsAnEmptyStateRatherThanBlankDetail() {
        let item = ChatItem.standaloneTool(id: "tool-empty", tool: listTool)
        let host = expandedHost(for: item, rows: [])

        XCTAssertTrue(labels(in: host).contains("No scheduled tasks"))
        XCTAssertNil(editButton(in: host))
    }

    /// The detail reads Alveary's own definitions, so a failed call must show the failure
    /// instead of a task list the tool never returned.
    func testFailedListShowsTheErrorRatherThanLiveTasks() {
        let item = ChatItem.standaloneTool(id: "tool-failed", tool: failedListTool)
        let host = expandedHost(for: item, rows: [Self.sampleRow])

        XCTAssertNil(editButton(in: host))
        XCTAssertTrue(labels(in: host).contains { $0.contains("does not accept arguments") })
    }

    private func editedDefinitionIDs(for item: ChatItem) throws -> [String] {
        var edited: [String] = []
        let host = expandedHost(for: item, rows: [Self.sampleRow]) { edited.append($0) }

        let button = try XCTUnwrap(
            editButton(in: host),
            "Expected an Edit button in the expanded scheduled-task list"
        )
        _ = button.target?.perform(button.action, with: button)
        return edited
    }

    private func expandedHost(
        for item: ChatItem,
        rows: [ScheduledTaskListRow],
        onEdit: @escaping @MainActor (String) -> Void = { _ in }
    ) -> NSView {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640
        configuration.expandedRowIDs = [item.id]
        configuration.scheduledTaskListActions = ScheduledTaskListToolActions(
            rows: { rows },
            onEdit: onEdit
        )

        let factory = AppKitTranscriptRowFactory()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        for row in factory.makeRows(for: [item], configuration: configuration) {
            row.view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
            host.addSubview(row.view)
        }
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// Both label kinds the detail can use: plain fields for rows, and the code surface's text
    /// view for an error.
    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField {
            found.append(field.stringValue)
        }
        if let textView = view as? NSTextView {
            found.append(textView.string)
        }
        for subview in view.subviews {
            found.append(contentsOf: labels(in: subview))
        }
        return found
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

    private var failedListTool: ToolEntry {
        ToolEntry(
            id: "tool-list-failed",
            name: ScheduledTaskHostToolCatalog.listToolName,
            summary: "List scheduled tasks",
            input: #"{"limit":5}"#,
            output: "\(ScheduledTaskHostToolCatalog.listToolName) does not accept arguments.",
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: true
        )
    }

    private static let sampleRow = ScheduledTaskListRow(
        id: "task-1",
        title: "Nightly audit",
        state: .active,
        scheduleSummary: "Daily at 2:00 AM"
    )
}
