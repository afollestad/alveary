@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptSubAgentBlockTests {
    func testExpandedAgentWithoutResultDoesNotRenderResultSection() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    resultAgent(description: "Map project structure", isComplete: true)
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Explored: Map project structure"))
        XCTAssertFalse(block.renderedText.contains("Result"))
    }

    func testMarkdownAgentResultUsesMarkdownRenderer() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    resultAgent(
                        description: "Map project structure",
                        result: """
                        ## Directory Structure Map

                        - One HTML entry point

                        ```text
                        index.html
                        ```
                        """,
                        isComplete: true
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertNotNil(block.descendants(of: AppKitMarkdownView.self).first)
        XCTAssertFalse(block.descendants(of: AppKitMarkdownCodeBlockView.self).isEmpty)
        XCTAssertTrue(block.renderedText.contains("Directory Structure Map"))
        XCTAssertFalse(block.renderedText.contains("## Directory Structure Map"))
        XCTAssertLessThan(block.intrinsicContentSize.height, 360)
    }

    func testCodeLikeAgentResultKeepsCodeSurface() {
        let block = AppKitTranscriptSubAgentBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                agents: [
                    resultAgent(
                        description: "Write helper",
                        result: """
                        func helper() {
                            print("ok")
                        }
                        """,
                        isComplete: true
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertNil(block.descendants(of: AppKitMarkdownView.self).first)
        XCTAssertNotNil(block.descendants(of: AppKitTranscriptDetailCodeBlockView.self).first)
        XCTAssertTrue(block.renderedText.contains("func helper()"))
    }

    func testMarkdownAgentResultClampsHorizontalScrollWhenWidened() throws {
        let block = AppKitTranscriptSubAgentBlockView()
        let wideLine = String(repeating: "wide ", count: 30)
        block.frame = NSRect(x: 0, y: 0, width: 260, height: 1_000)
        block.configure(
            .init(
                agents: [
                    resultAgent(
                        description: "Map project structure",
                        result: """
                        ## Directory Structure Map

                        ```text
                        \(wideLine)
                        ```
                        """,
                        isComplete: true
                    )
                ],
                initiallyExpanded: true
            )
        )
        block.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(block.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        let initialMaxX = max((scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width, 0)
        XCTAssertGreaterThan(initialMaxX, 0)
        scrollView.contentView.scroll(to: NSPoint(x: initialMaxX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)

        block.frame = NSRect(x: 0, y: 0, width: 1_400, height: 1_000)
        block.layoutSubtreeIfNeeded()

        let maxX = max((scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width, 0)
        XCTAssertLessThanOrEqual(scrollView.contentView.bounds.origin.x, maxX + 0.5)
        if maxX < 0.5 {
            XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
        }
    }
}

private func resultAgent(
    id: String = "agent-one",
    description: String,
    result: String? = nil,
    isComplete: Bool = false
) -> SubAgentEntry {
    SubAgentEntry(
        id: id,
        agentType: "explorer",
        description: description,
        statusDescription: nil,
        lastToolName: nil,
        tools: [],
        result: result,
        isComplete: isComplete,
        toolUseCount: 0
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
