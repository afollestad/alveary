@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testMarkdownEditStaysCollapsedWhenCompletedUntilUserExpands() {
        let row = AppKitTranscriptInlineToolRowView()
        let input = #"{"file_path":"/tmp/plan.md","old_string":"Done.","new_string":"Done.\n\nLorem ipsum."}"#
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "Edit",
                    summary: "Edit `plan.md`",
                    input: input
                )
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)

        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "Edit",
                    summary: "Edit `plan.md`",
                    input: input,
                    output: "Updated",
                    isComplete: true
                )
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Lorem ipsum."))
    }

    func testCompletedMarkdownWriteStaysCollapsedOnFirstMountUntilUserExpands() {
        let row = AppKitTranscriptInlineToolRowView()
        let input = ##"{"file_path":"/tmp/let-s-test-plan-mode-peppy-puzzle.md","content":"# Plan\n\n- Keep tools collapsed."}"##
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "Write",
                    summary: "Write `let-s-test-plan-mode-peppy-puzzle.md`",
                    input: input,
                    output: "Wrote file",
                    isComplete: true
                )
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Keep tools collapsed."))
    }

    func testMarkdownMultiEditDetailsUseAppKitMarkdownRenderer() {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "MultiEdit",
                    summary: "MultiEdit `plan.md`",
                    input: """
                    {
                      "file_path": "/tmp/plan.md",
                      "edits": [
                        {"old_string": "First", "new_string": "## First"},
                        {"old_string": "Second", "new_string": "- Second"}
                      ]
                    }
                    """,
                    output: "Updated",
                    isComplete: true
                ),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.markdownMutationRenderedText.contains("First"))
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Second"))
    }
}

private func markdownMutationTool(
    id: String = "tool-1",
    name: String,
    summary: String,
    input: String,
    output: String? = nil,
    isComplete: Bool = false
) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: input,
        output: output,
        stderr: nil,
        isComplete: isComplete,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

private extension NSView {
    var markdownMutationRenderedText: String {
        markdownMutationDescendants(of: NSTextField.self).map(\.stringValue).joined(separator: "\n") + "\n"
            + markdownMutationDescendants(of: AppKitMarkdownTextView.self).map(\.string).joined(separator: "\n")
    }

    func markdownMutationDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.markdownMutationDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
