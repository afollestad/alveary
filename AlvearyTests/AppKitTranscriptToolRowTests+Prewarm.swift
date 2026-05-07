@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testPrewarmedCollapsedToolDetailsStayHiddenUntilExpansion() async {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        row.configure(
            .init(tool: prewarmTool())
        )
        row.layoutSubtreeIfNeeded()
        await Task.yield()
        row.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.renderedTextForPrewarmTesting.contains("Output"))

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.renderedTextForPrewarmTesting.contains("Output"))
        XCTAssertTrue(row.renderedTextForPrewarmTesting.contains("line 1"))
    }
}

private func prewarmTool() -> ToolEntry {
    ToolEntry(
        id: "tool-1",
        name: "CustomTool",
        summary: "Running `swift test`",
        input: #"{"command":"swift test"}"#,
        output: "line 1",
        stderr: nil,
        isComplete: true,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
}

private extension NSView {
    var renderedTextForPrewarmTesting: String {
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
