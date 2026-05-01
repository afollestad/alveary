@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptToolRowTests: XCTestCase {
    func testHeaderUsesSharedSummaryFormatterForSlashCommandChips() {
        let header = AppKitTranscriptToolHeaderRowView()
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Running /compact in `pwd`",
                leadingIcon: .disclosure(isExpanded: false),
                phase: .loading
            )
        )
        header.layoutSubtreeIfNeeded()

        guard let textStorage = header.descendants(of: NSTextField.self).first?.attributedStringValue else {
            return XCTFail("Expected header summary text")
        }
        let commandRange = (textStorage.string as NSString).range(of: "/compact")
        let codeRange = (textStorage.string as NSString).range(of: "pwd")

        XCTAssertNotEqual(commandRange.location, NSNotFound)
        XCTAssertNotNil(textStorage.attribute(.backgroundColor, at: commandRange.location, effectiveRange: nil))
        XCTAssertNotNil(textStorage.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil))
    }

    func testHeaderAccessibilityPressTogglesExpansion() {
        let header = AppKitTranscriptToolHeaderRowView()
        var pressCount = 0
        header.onToggle = {
            pressCount += 1
        }
        header.configure(
            .init(
                summary: "Running tool",
                leadingIcon: .disclosure(isExpanded: false),
                phase: .loading
            )
        )

        XCTAssertTrue(header.accessibilityPerformPress())
        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(header.accessibilityValue() as? String, "collapsed")
    }

    func testExpandedDisclosureDoesNotRotateIconLayerOutOfFrame() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        header.configure(
            .init(
                summary: "Reading file",
                leadingIcon: .disclosure(isExpanded: true),
                phase: .loading
            )
        )
        header.layoutSubtreeIfNeeded()

        let icon = try XCTUnwrap(header.descendants(of: NSImageView.self).first)
        XCTAssertEqual(icon.layer?.affineTransform(), .identity)
        XCTAssertEqual(header.accessibilityValue() as? String, "expanded")
    }

    func testHeaderStatusIconUsesTranscriptTypography() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        var settings = AppSettings()
        settings.chatFontSize = 24
        let typography = TranscriptTypography(settings: settings)

        header.configure(
            .init(
                summary: "Read file",
                leadingIcon: .disclosure(isExpanded: false),
                phase: .success,
                typography: typography
            )
        )

        let statusView = try XCTUnwrap(header.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        XCTAssertEqual(statusView.statusSymbolPointSizeForTesting, typography.size(for: .toolStatusIcon))
    }

    func testSkillRowStaysNonExpandable() {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        row.configure(
            .init(
                tool: tool(name: "Skill", summary: "Invoking skill `self-review-alveary`", output: "details"),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()
        let initialHeight = row.intrinsicContentSize.height

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.intrinsicContentSize.height, initialHeight)
        XCTAssertFalse(row.renderedText.contains("Input"))
    }

    func testInlineToolExpansionInvalidatesHeightAndShowsDetails() {
        let row = AppKitTranscriptInlineToolRowView()
        var invalidated = false
        row.onHeightInvalidated = {
            invalidated = true
        }
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        row.configure(
            .init(tool: tool(name: "CustomTool", summary: "Running `swift test`", output: (1...20).map { "line \($0)" }.joined(separator: "\n")))
        )
        row.layoutSubtreeIfNeeded()
        let collapsedHeight = row.intrinsicContentSize.height
        invalidated = false

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, collapsedHeight)
        XCTAssertTrue(row.renderedText.contains("Output"))
        XCTAssertTrue(row.renderedText.contains("line 20"))
    }

    func testInlineToolIgnoresPersistedExpansionEchoAfterLocalToggle() {
        let row = AppKitTranscriptInlineToolRowView()
        var invalidationCount = 0
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        let entry = tool(name: "CustomTool", summary: "Running `swift test`", output: "output")
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        row.configure(.init(tool: entry, initiallyExpanded: false))
        row.layoutSubtreeIfNeeded()

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()
        invalidationCount = 0

        row.configure(.init(tool: entry, initiallyExpanded: true))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(invalidationCount, 0)
        XCTAssertTrue(row.renderedText.contains("Output"))
    }

    func testToolGroupSummarizesAndExpandsNestedRows() {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md"),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for LazyVStack")
                ]
            )
        )
        group.layoutSubtreeIfNeeded()
        let collapsedHeight = group.intrinsicContentSize.height

        XCTAssertTrue(group.renderedText.contains("Reading 1 file, searching for 1 pattern"))

        group.setExpanded(true)
        group.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(group.intrinsicContentSize.height, collapsedHeight)
        XCTAssertTrue(group.renderedText.contains("Reading AGENTS.md"))
        XCTAssertTrue(group.renderedText.contains("Searching for LazyVStack"))
    }

    func testToolGroupIgnoresPersistedExpansionEchoAfterLocalToggle() {
        let group = AppKitTranscriptToolGroupView()
        var invalidationCount = 0
        group.onHeightInvalidated = {
            invalidationCount += 1
        }
        let tools = [
            tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md"),
            tool(id: "grep-1", name: "Grep", summary: "Searching for LazyVStack")
        ]
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(.init(tools: tools, initiallyExpanded: false))
        group.layoutSubtreeIfNeeded()

        group.setExpanded(true)
        group.layoutSubtreeIfNeeded()
        invalidationCount = 0

        group.configure(.init(tools: tools, initiallyExpanded: true))
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(invalidationCount, 0)
        XCTAssertTrue(group.renderedText.contains("Reading AGENTS.md"))
    }

    func testNestedToolExpansionInvalidatesGroupHeight() throws {
        let group = AppKitTranscriptToolGroupView()
        var invalidated = false
        group.onHeightInvalidated = {
            invalidated = true
        }
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    tool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Running custom tool",
                        output: (0..<18).map { "nested output line \($0)" }.joined(separator: "\n")
                    ),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()
        let collapsedToolHeight = group.intrinsicContentSize.height
        invalidated = false

        let nestedRows = try XCTUnwrap(group.descendants(of: AppKitTranscriptNestedToolRowsView.self).first)
        let firstNestedHeader = try XCTUnwrap(nestedRows.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        group.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(group.intrinsicContentSize.height, collapsedToolHeight)
        XCTAssertTrue(group.renderedText.contains("nested output line 17"))
    }

    func testNestedToolExpansionSurvivesParentRefresh() throws {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    tool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Running custom tool",
                        output: (0..<12).map { "nested output line \($0)" }.joined(separator: "\n")
                    ),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()
        let nestedRows = try XCTUnwrap(group.descendants(of: AppKitTranscriptNestedToolRowsView.self).first)
        let firstNestedHeader = try XCTUnwrap(nestedRows.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        group.layoutSubtreeIfNeeded()
        XCTAssertTrue(group.renderedText.contains("nested output line 11"))

        group.configure(
            .init(
                tools: [
                    tool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Finished custom tool",
                        output: (0..<12).map { "nested output line \($0)" }.joined(separator: "\n"),
                        isComplete: true
                    ),
                    tool(id: "grep-1", name: "Grep", summary: "Searched for AppKit", isComplete: true)
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()

        XCTAssertTrue(group.renderedText.contains("nested output line 11"))
    }

    func testToolGroupSummarySwitchesToPastTenseWhenComplete() {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md", isComplete: true),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for LazyVStack", isComplete: true)
                ]
            )
        )
        group.layoutSubtreeIfNeeded()

        XCTAssertTrue(group.renderedText.contains("Read 1 file, searched for 1 pattern"))
    }

    func testToolGroupDebouncesTerminalStatusAfterLoading() async throws {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md"),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for LazyVStack")
                ]
            )
        )
        group.layoutSubtreeIfNeeded()

        group.configure(
            .init(
                tools: [
                    tool(id: "read-1", name: "Read", summary: "Reading AGENTS.md", isComplete: true),
                    tool(id: "grep-1", name: "Grep", summary: "Searching for LazyVStack", isComplete: true)
                ]
            )
        )
        group.layoutSubtreeIfNeeded()

        let statusView = try XCTUnwrap(group.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)

        XCTAssertFalse(statusView.descendants(of: NSProgressIndicator.self).first?.isHidden ?? true)

        try await waitUntil("expected terminal tool-group status after debounce", timeout: .seconds(1)) {
            let progressHidden = statusView.descendants(of: NSProgressIndicator.self).first?.isHidden ?? false
            let hasSymbol = !statusView.descendants(of: NSImageView.self).filter { $0.image != nil }.isEmpty
            return progressHidden && hasSymbol
        }
    }

    func testEmptyToolGroupClearsStaleSingleRowHeight() {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(.init(tools: [tool(name: "Read", summary: "Reading AGENTS.md")]))
        group.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(group.intrinsicContentSize.height, 0)

        group.configure(.init(tools: []))
        group.layoutSubtreeIfNeeded()

        XCTAssertEqual(group.intrinsicContentSize.height, 0)
        XCTAssertTrue(group.renderedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testReadMarkdownDetailsUseAppKitMarkdownRenderer() {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: tool(
                    name: "Read",
                    summary: "Reading README.md",
                    input: #"{"file_path":"/tmp/README.md"}"#,
                    output: "1\t# Title\n2\tBody with `code`.",
                    isComplete: true
                ),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.descendants(of: AppKitMarkdownView.self).isEmpty)
        XCTAssertTrue(row.renderedText.contains("Title"))
    }

    func testReadMarkdownTaskStateIsScopedByToolID() {
        let first = markdownReadRow(id: "read-one")
        let second = markdownReadRow(id: "read-two")

        XCTAssertEqual(first.descendants(of: AppKitMarkdownTaskCheckbox.self).first?.state, .off)
        XCTAssertEqual(second.descendants(of: AppKitMarkdownTaskCheckbox.self).first?.state, .off)

        first.descendants(of: AppKitMarkdownTaskCheckbox.self).first?.performClick(nil)

        XCTAssertEqual(first.descendants(of: AppKitMarkdownTaskCheckbox.self).first?.state, .on)
        XCTAssertEqual(second.descendants(of: AppKitMarkdownTaskCheckbox.self).first?.state, .off)
    }

    func testReadMarkdownForwardsLinkClicks() throws {
        let row = AppKitTranscriptInlineToolRowView()
        var openedURL: URL?
        row.onOpenMarkdownLink = { openedURL = $0 }
        row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        row.configure(
            .init(
                tool: tool(
                    name: "Read",
                    summary: "Reading README.md",
                    input: #"{"file_path":"/tmp/README.md"}"#,
                    output: "1\tSee [docs](GUIDE.md).",
                    isComplete: true
                ),
                initiallyExpanded: true
            )
        )
        row.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(
            row.descendants(of: AppKitMarkdownTextView.self).first { $0.string.contains("docs") }
        )
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "docs"))

        XCTAssertTrue(textView.textView(textView, clickedOnLink: link, at: 0))
        XCTAssertEqual(openedURL?.lastPathComponent, "GUIDE.md")
    }
}

@MainActor
private func markdownReadRow(id: String) -> AppKitTranscriptInlineToolRowView {
    let row = AppKitTranscriptInlineToolRowView()
    row.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
    row.configure(
        .init(
            tool: tool(
                id: id,
                name: "Read",
                summary: "Reading TODO.md",
                input: #"{"file_path":"/tmp/TODO.md"}"#,
                output: "1\t- [ ] Shared task",
                isComplete: true
            ),
            initiallyExpanded: true
        )
    )
    row.layoutSubtreeIfNeeded()
    return row
}

private func tool(
    id: String = "tool-1",
    name: String,
    summary: String,
    input: String = #"{"command":"echo hi"}"#,
    output: String? = nil,
    stderr: String? = nil,
    isComplete: Bool = false,
    isError: Bool = false
) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: input,
        output: output,
        stderr: stderr,
        isComplete: isComplete,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: isError
    )
}

@MainActor
private func linkAttribute(in textView: AppKitMarkdownTextView, matching text: String) -> Any? {
    let range = (textView.string as NSString).range(of: text)
    guard range.location != NSNotFound else {
        return nil
    }
    return textView.textStorage?.attribute(.link, at: range.location, effectiveRange: nil)
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
