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

    func testMarkdownEditPreviewOverrideRendersFullDocument() {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "Edit",
                    summary: "Edit `plan.md`",
                    input: #"{"file_path":"/tmp/plan.md","old_string":"- Existing","new_string":"- Existing\n- Follow-up"}"#,
                    output: "Updated",
                    isComplete: true,
                    previewOverride: ToolContentPreview(
                        content: "# Plan\n\n- Existing\n- Follow-up",
                        language: "markdown",
                        baseURL: URL(fileURLWithPath: "/tmp")
                    )
                ),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Plan"))
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Existing"))
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Follow-up"))
    }

    func testMarkdownEditPreviewKeepsRenderedTextInsideChrome() throws {
        let row = AppKitTranscriptInlineToolRowView()
        let input = try markdownEditInput(
            filePath: "/tmp/AGENTS.md",
            oldString: "- Old guidance",
            newString: """
            - Bounded preview text should stay below the rounded surface border even when the line wraps in the summary column.
            - Second list item
            """
        )
        row.frame = NSRect(x: 0, y: 0, width: 720, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    name: "Edit",
                    summary: "Edit `AGENTS.md`",
                    input: input,
                    output: "Updated",
                    isComplete: true
                ),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()

        let markdownView = try XCTUnwrap(row.markdownMutationDescendants(of: AppKitMarkdownView.self).first)
        let chromeView = try XCTUnwrap(markdownView.superview)
        let textViews = chromeView.markdownMutationDescendants(of: AppKitMarkdownTextView.self)

        XCTAssertFalse(textViews.isEmpty)
        XCTAssertTrue(chromeView.clipsToBounds)
        XCTAssertTrue(chromeView.layer?.masksToBounds ?? false)
        XCTAssertEqual(markdownView.frame.minY, 10, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(chromeView.bounds.height, markdownView.frame.maxY + 10 - 0.5)

        for textView in textViews {
            let textFrame = chromeView.convert(textView.bounds, from: textView)
            XCTAssertGreaterThanOrEqual(textFrame.minY, -0.5)
            XCTAssertLessThanOrEqual(textFrame.maxY, chromeView.bounds.height + 0.5)
        }
    }

    func testMarkdownEditDetailsRefreshWhenPreviewOverrideArrivesForReusedCollapsedRow() throws {
        let row = AppKitTranscriptInlineToolRowView()
        let input = #"{"file_path":"/tmp/plan.md","old_string":"- Existing","new_string":"- Existing\n- Follow-up"}"#
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: markdownMutationTool(
                    id: "edit-1",
                    name: "Edit",
                    summary: "Edit `plan.md`",
                    input: input,
                    output: "Updated",
                    isComplete: true
                )
            )
        )
        row.layoutSubtreeIfNeeded()
        row.prewarmDetailsIfNeededForTesting()
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertEqual(row.prewarmedDetailsToolForTesting?.previewOverride, nil)
        XCTAssertFalse(row.prewarmedDetailsRenderedTextForTesting.contains("Plan"))

        row.configure(
            .init(
                tool: markdownMutationTool(
                    id: "edit-1",
                    name: "Edit",
                    summary: "Edit `plan.md`",
                    input: input,
                    output: "Updated",
                    isComplete: true,
                    previewOverride: ToolContentPreview(
                        content: "# Plan\n\n- Existing\n- Follow-up",
                        language: "markdown",
                        baseURL: nil
                    )
                )
            )
        )
        row.layoutSubtreeIfNeeded()
        row.prewarmDetailsIfNeededForTesting()
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownMutationDescendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertNotNil(row.prewarmedDetailsToolForTesting?.previewOverride)
        XCTAssertTrue(row.prewarmedDetailsRenderedTextForTesting.contains("Plan"))

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Plan"))
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Existing"))
        XCTAssertTrue(row.markdownMutationRenderedText.contains("Follow-up"))
    }
}

private func markdownMutationTool(
    id: String = "tool-1",
    name: String,
    summary: String,
    input: String,
    output: String? = nil,
    isComplete: Bool = false,
    previewOverride: ToolContentPreview? = nil
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
        isError: false,
        previewOverride: previewOverride
    )
}

private func markdownEditInput(filePath: String, oldString: String, newString: String) throws -> String {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "file_path": filePath,
            "old_string": oldString,
            "new_string": newString
        ],
        options: [.sortedKeys]
    )
    return try XCTUnwrap(String(data: data, encoding: .utf8))
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
