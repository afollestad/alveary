@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testNestedToolExpansionAndCollapseInvalidatesGroupHeight() throws {
        let group = AppKitTranscriptToolGroupView()
        var invalidated = false
        group.onHeightInvalidated = { invalidated = true }
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    nestedToolRowTool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Running custom tool",
                        output: (0..<18).map { "nested output line \($0)" }.joined(separator: "\n")
                    ),
                    nestedToolRowTool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()
        let collapsedToolHeight = group.intrinsicContentSize.height
        invalidated = false

        let nestedRows = try XCTUnwrap(descendants(of: AppKitTranscriptNestedToolRowsView.self, in: group).first)
        let firstNestedHeader = try XCTUnwrap(descendants(of: AppKitTranscriptToolHeaderRowView.self, in: nestedRows).first)
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        group.layoutSubtreeIfNeeded()
        let nestedToolRow = try XCTUnwrap(firstNestedHeader.superview?.superview as? AppKitTranscriptInlineToolRowView)
        let expandedHeight = group.intrinsicContentSize.height

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(expandedHeight, collapsedToolHeight)
        XCTAssertTrue(nestedToolRow.clipsToBounds)
        XCTAssertTrue(renderedText(in: group).contains("nested output line 17"))

        invalidated = false
        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())
        let heightAfterCollapseInvalidation = group.intrinsicContentSize.height

        XCTAssertTrue(invalidated)
        XCTAssertLessThan(heightAfterCollapseInvalidation, expandedHeight)
        group.layoutSubtreeIfNeeded()
        XCTAssertLessThan(group.intrinsicContentSize.height, expandedHeight)
        XCTAssertFalse(renderedText(in: group).contains("nested output line 17"))
    }

    func testNestedToolExpansionReportsUserHeightChangeBeforeInvalidation() throws {
        let group = AppKitTranscriptToolGroupView()
        var events: [String] = []
        group.onUserInitiatedHeightChange = { events.append("user") }
        group.onHeightInvalidated = { events.append("height") }
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        group.configure(
            .init(
                tools: [
                    nestedToolRowTool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Running custom tool",
                        output: (0..<18).map { "nested output line \($0)" }.joined(separator: "\n")
                    ),
                    nestedToolRowTool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()
        let nestedRows = try XCTUnwrap(descendants(of: AppKitTranscriptNestedToolRowsView.self, in: group).first)
        let firstNestedHeader = try XCTUnwrap(descendants(of: AppKitTranscriptToolHeaderRowView.self, in: nestedRows).first)
        events = []

        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }

    func testNestedToolExpansionClipsColdContentDuringFirstAnimation() throws {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 460, height: 1_000)
        let window = NSWindow(contentRect: group.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = group
        group.configure(
            .init(
                tools: [
                    nestedToolRowTool(
                        id: "custom-1",
                        name: "CustomTool",
                        summary: "Running custom tool",
                        output: (0..<24).map { "nested output line \($0)" }.joined(separator: "\n")
                    ),
                    nestedToolRowTool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                initiallyExpanded: true
            )
        )
        group.layoutSubtreeIfNeeded()
        let nestedRows = try XCTUnwrap(descendants(of: AppKitTranscriptNestedToolRowsView.self, in: group).first)
        let firstNestedHeader = try XCTUnwrap(descendants(of: AppKitTranscriptToolHeaderRowView.self, in: nestedRows).first)
        let nestedToolRow = try XCTUnwrap(firstNestedHeader.superview?.superview as? AppKitTranscriptInlineToolRowView)
        let clipView = try XCTUnwrap(descendants(of: AppKitTranscriptExpandableClipView.self, in: nestedToolRow).first)
        let collapsedClipHeight = clipView.visibleHeightForTesting

        XCTAssertTrue(firstNestedHeader.accessibilityPerformPress())

        XCTAssertEqual(clipView.visibleHeightForTesting, collapsedClipHeight, accuracy: 0.5)
        XCTAssertGreaterThan(nestedToolRow.intrinsicContentSize.height, collapsedClipHeight)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: appExpansionAnimationDuration + 0.4))

        XCTAssertFalse(clipView.isAnimatingVisibleHeight)
        XCTAssertEqual(clipView.visibleHeightForTesting, nestedToolRow.intrinsicContentSize.height, accuracy: 0.5)
        window.contentView = nil
    }
}

private func nestedToolRowTool(
    id: String,
    name: String,
    summary: String,
    output: String? = nil
) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: #"{"command":"echo hi"}"#,
        output: output,
        stderr: nil,
        isComplete: false,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

@MainActor
private func renderedText(in view: NSView) -> String {
    descendants(of: NSTextField.self, in: view).map { $0.stringValue }.joined(separator: "\n") + "\n"
        + descendants(of: AppKitMarkdownTextView.self, in: view).map { $0.string }.joined(separator: "\n")
}

@MainActor
private func descendants<ViewType: NSView>(of type: ViewType.Type, in view: NSView) -> [ViewType] {
    view.subviews.flatMap { child -> [ViewType] in
        var matches = descendants(of: type, in: child)
        if let typed = child as? ViewType {
            matches.insert(typed, at: 0)
        }
        return matches
    }
}
