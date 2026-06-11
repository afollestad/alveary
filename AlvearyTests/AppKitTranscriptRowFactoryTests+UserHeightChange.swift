@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testToolExpansionReportsUserHeightChangeBeforeInvalidation() throws {
        let factory = AppKitTranscriptRowFactory()
        var events: [String] = []
        let rows = factory.makeRows(
            for: [.standaloneTool(id: "standalone", tool: userHeightTool(id: "read"))],
            configuration: .init(
                onRowHeightInvalidated: { _, _ in events.append("height") },
                onUserInitiatedHeightChange: { events.append("user") }
            )
        )
        let row = try XCTUnwrap(rows.first?.view as? AppKitTranscriptInlineToolRowView)
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.layoutSubtreeIfNeeded()
        events = []

        row.setExpanded(true)

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }

    func testSingleEntryToolGroupExpansionReportsUserHeightChangeBeforeInvalidation() throws {
        let factory = AppKitTranscriptRowFactory()
        var events: [String] = []
        let rows = factory.makeRows(
            for: [.toolGroup(id: "single-tool", tools: [userHeightTool(id: "read")])],
            configuration: .init(
                onRowHeightInvalidated: { _, _ in events.append("height") },
                onUserInitiatedHeightChange: { events.append("user") }
            )
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.layoutSubtreeIfNeeded()
        let singleToolRow = try XCTUnwrap(group.descendants(of: AppKitTranscriptInlineToolRowView.self).first)
        events = []

        singleToolRow.setExpanded(true)

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }

    func testSubAgentExpansionReportsUserHeightChangeBeforeInvalidation() throws {
        let factory = AppKitTranscriptRowFactory()
        var events: [String] = []
        let rows = factory.makeRows(
            for: [.subAgentBlock(id: "agents", agents: [userHeightAgent(id: "agent")])],
            configuration: .init(
                onRowHeightInvalidated: { _, _ in events.append("height") },
                onUserInitiatedHeightChange: { events.append("user") }
            )
        )
        let block = try XCTUnwrap(rows.first?.view as? AppKitTranscriptSubAgentBlockView)
        block.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        block.layoutSubtreeIfNeeded()
        events = []

        block.setExpanded(true)

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }
}

private func userHeightTool(id: String) -> ToolEntry {
    ToolEntry(
        id: id,
        name: "Read",
        summary: "Read file",
        input: "{}",
        output: nil,
        stderr: nil,
        isComplete: true,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

private func userHeightAgent(id: String) -> SubAgentEntry {
    SubAgentEntry(
        id: id,
        agentType: "explorer",
        description: "Inspect code",
        tools: [],
        result: "Expandable result",
        isComplete: false,
        toolUseCount: 0
    )
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
