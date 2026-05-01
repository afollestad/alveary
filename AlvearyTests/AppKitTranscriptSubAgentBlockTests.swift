@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptSubAgentBlockTests: XCTestCase {
    func testSingleAgentSummaryAndExpansionShowsToolsDirectly() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(agents: [agent(description: "Inspect transcript rows", tools: [tool(name: "Read", summary: "Reading AGENTS.md")])])
        )
        block.layoutSubtreeIfNeeded()
        let collapsedHeight = block.intrinsicContentSize.height

        XCTAssertTrue(block.renderedText.contains("Exploring: Inspect transcript rows"))

        block.setExpanded(true)
        block.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(block.intrinsicContentSize.height, collapsedHeight)
        XCTAssertTrue(block.renderedText.contains("Reading AGENTS.md"))
    }

    func testMultiAgentBlockOpensNestedAgentsByDefaultWhenExpanded() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    agent(
                        id: "agent-one",
                        description: "Inspect transcript rows",
                        tools: [tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md")],
                        result: (0..<16).map { "nested result line \($0)" }.joined(separator: "\n")
                    ),
                    agent(
                        id: "agent-two",
                        description: "Search code paths",
                        tools: [tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")]
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Exploring 2 sub-agents"))
        XCTAssertTrue(block.renderedText.contains("Inspect transcript rows"))
        XCTAssertTrue(block.renderedText.contains("Reading AGENTS.md"))
        XCTAssertTrue(block.renderedText.contains("Search code paths"))
        XCTAssertTrue(block.renderedText.contains("Searching for AppKit"))
    }

    func testNestedAgentCollapseInvalidatesHeight() throws {
        let block = AppKitTranscriptSubAgentBlockView()
        var invalidated = false
        block.onHeightInvalidated = {
            invalidated = true
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    agent(
                        id: "agent-one",
                        description: "Inspect transcript rows",
                        tools: [tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md")],
                        result: (0..<16).map { "nested result line \($0)" }.joined(separator: "\n")
                    ),
                    agent(
                        id: "agent-two",
                        description: "Search code paths",
                        tools: [tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")]
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()
        let expandedHeight = block.intrinsicContentSize.height
        invalidated = false

        let nestedRows = try XCTUnwrap(block.descendants(of: AppKitTranscriptNestedSubAgentRowsView.self).first)
        let firstNestedHeader = try XCTUnwrap(nestedRows.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertLessThan(block.intrinsicContentSize.height, expandedHeight)
        XCTAssertFalse(block.renderedText.contains("nested result line 15"))
    }

    func testNestedAgentExpansionStateSurvivesParentRefresh() throws {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    agent(
                        id: "agent-one",
                        description: "Inspect transcript rows",
                        tools: [tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md")],
                        result: (0..<12).map { "nested result line \($0)" }.joined(separator: "\n")
                    ),
                    agent(
                        id: "agent-two",
                        description: "Search code paths",
                        tools: [tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")]
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()
        let nestedRows = try XCTUnwrap(block.descendants(of: AppKitTranscriptNestedSubAgentRowsView.self).first)
        let firstNestedHeader = try XCTUnwrap(nestedRows.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        block.layoutSubtreeIfNeeded()
        XCTAssertFalse(block.renderedText.contains("nested result line 11"))

        block.configure(
            .init(
                agents: [
                    agent(
                        id: "agent-one",
                        description: "Inspected transcript rows",
                        tools: [tool(id: "read-1", name: "Read", summary: "Read AGENTS.md", isComplete: true)],
                        result: (0..<12).map { "nested result line \($0)" }.joined(separator: "\n"),
                        isComplete: true
                    ),
                    agent(
                        id: "agent-two",
                        description: "Search code paths",
                        tools: [tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")]
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertFalse(block.renderedText.contains("nested result line 11"))
    }

    func testCompletedMultiAgentSummaryUsesPastTense() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    agent(id: "agent-one", description: "Inspect transcript rows", isComplete: true),
                    agent(id: "agent-two", description: "Search code paths", isComplete: true)
                ]
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Explored 2 sub-agents"))
    }

    func testAgentResultInvalidatesHeight() {
        let block = AppKitTranscriptSubAgentBlockView()
        var invalidated = false
        block.onHeightInvalidated = {
            invalidated = true
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    agent(description: "Summarize findings", result: "Short result")
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()
        let shortHeight = block.intrinsicContentSize.height
        invalidated = false

        block.configure(
            .init(
                agents: [
                    agent(description: "Summarize findings", result: (0..<20).map { "result line \($0)" }.joined(separator: "\n"))
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(block.intrinsicContentSize.height, shortHeight)
        XCTAssertTrue(block.renderedText.contains("Result"))
        XCTAssertTrue(block.renderedText.contains("result line 19"))
    }
}

private func agent(
    id: String = "agent-one",
    description: String,
    tools: [ToolEntry] = [],
    result: String? = nil,
    isComplete: Bool = false
) -> SubAgentEntry {
    SubAgentEntry(
        id: id,
        agentType: "explorer",
        description: description,
        statusDescription: nil,
        lastToolName: nil,
        tools: tools,
        result: result,
        isComplete: isComplete,
        toolUseCount: tools.count
    )
}

private func tool(
    id: String = "tool-one",
    name: String,
    summary: String,
    isComplete: Bool = false,
    isError: Bool = false
) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: #"{"path":"AGENTS.md"}"#,
        output: nil,
        stderr: nil,
        isComplete: isComplete,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: isError
    )
}

private extension NSView {
    var renderedText: String {
        descendants(of: NSTextField.self).map(\.stringValue).joined(separator: "\n") + "\n"
            + descendants(of: AppKitMarkdownTextView.self).map(\.string).joined(separator: "\n")
    }

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
