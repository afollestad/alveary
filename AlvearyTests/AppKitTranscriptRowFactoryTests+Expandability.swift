@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptRowFactoryTests {
    func testNoOutputExpectedToolWithoutContentIsNotExpandable() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.standaloneTool(id: "tool-bash", tool: noOutputCommandTool(id: "bash"))],
            configuration: .init(
                expandedRowIDs: ["tool-bash"],
                onRowExpansionChanged: { rowID, isExpanded in
                    expansionChanges.append((rowID, isExpanded))
                }
            )
        )
        let row = try XCTUnwrap(rows.first?.view as? AppKitTranscriptInlineToolRowView)

        row.setExpanded(true)

        XCTAssertTrue(row.descendants(of: AppKitTranscriptToolDetailsView.self).isEmpty)
        XCTAssertTrue(expansionChanges.isEmpty)
    }

    func testSingleToolGroupNoOutputExpectedToolUsesGroupIdButIsNotExpandable() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.toolGroup(id: "group-bash", tools: [noOutputCommandTool(id: "bash")])],
            configuration: .init(
                expandedRowIDs: ["group-bash"],
                onRowExpansionChanged: { rowID, isExpanded in
                    expansionChanges.append((rowID, isExpanded))
                }
            )
        )
        let group = try XCTUnwrap(rows.first?.view as? AppKitTranscriptToolGroupView)
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 400)
        group.layoutSubtreeIfNeeded()
        let singleToolRow = try XCTUnwrap(group.descendants(of: AppKitTranscriptInlineToolRowView.self).first)

        singleToolRow.setExpanded(true)

        XCTAssertTrue(expansionChanges.isEmpty)
    }

    func testEmptySubAgentBlockIsNotExpandable() throws {
        let factory = AppKitTranscriptRowFactory()
        var expansionChanges: [(rowID: String, isExpanded: Bool)] = []
        let rows = factory.makeRows(
            for: [.subAgentBlock(id: "agents", agents: [emptyAgent(id: "agent")])],
            configuration: .init(
                expandedRowIDs: ["agents"],
                onRowExpansionChanged: { rowID, isExpanded in
                    expansionChanges.append((rowID, isExpanded))
                }
            )
        )
        let block = try XCTUnwrap(rows.first?.view as? AppKitTranscriptSubAgentBlockView)

        block.setExpanded(true)

        XCTAssertTrue(expansionChanges.isEmpty)
    }

    private func noOutputCommandTool(id: String) -> ToolEntry {
        ToolEntry(
            id: id,
            name: "Bash",
            summary: "Ran `true`",
            input: #"{"command":"true"}"#,
            output: nil,
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: true,
            isError: false
        )
    }

    private func emptyAgent(id: String) -> SubAgentEntry {
        SubAgentEntry(
            id: id,
            agentType: "explorer",
            description: "Inspect code",
            tools: [],
            result: nil,
            isComplete: true,
            toolUseCount: 0
        )
    }
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
