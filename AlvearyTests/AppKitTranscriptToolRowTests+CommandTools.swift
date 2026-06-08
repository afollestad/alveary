@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testCommandExecutionUsesCommandHeaderAndMinimalOutputDetails() throws {
        let runningRow = AppKitTranscriptInlineToolRowView()
        runningRow.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        runningRow.configure(
            .init(
                tool: commandTool(
                    summary: "CommandExecution",
                    input: #"{"command":"swift test","commandActions":[{"command":"ignored"}]}"#
                )
            )
        )
        runningRow.layoutSubtreeIfNeeded()

        XCTAssertTrue(runningRow.renderedTextForCommandToolTests.contains("Running swift test"))
        let header = try XCTUnwrap(runningRow.descendantsForCommandToolTests(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertNil(header.accessibilityValue(), "Command-like rows should use the dollarsign icon instead of disclosure state copy")

        let completedRow = AppKitTranscriptInlineToolRowView()
        completedRow.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        completedRow.configure(
            .init(
                tool: commandTool(
                    summary: "Executing `swift test`",
                    input: #"{"command":"swift test","commandActions":[{"command":"ignored"}]}"#,
                    output: (1...12).map { "line \($0)" }.joined(separator: "\n"),
                    isComplete: true
                ),
                initiallyExpanded: true
            )
        )
        completedRow.layoutSubtreeIfNeeded()

        XCTAssertTrue(completedRow.renderedTextForCommandToolTests.contains("Ran swift test"))
        XCTAssertTrue(completedRow.renderedTextForCommandToolTests.contains("line 12"))
        XCTAssertFalse(completedRow.renderedTextForCommandToolTests.contains("Input"))
        XCTAssertFalse(completedRow.renderedTextForCommandToolTests.contains("commandActions"))
    }
}

private func commandTool(
    summary: String,
    input: String,
    output: String? = nil,
    isComplete: Bool = false
) -> ToolEntry {
    ToolEntry(
        id: "command-tool",
        name: "CommandExecution",
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
    var renderedTextForCommandToolTests: String {
        descendantsForCommandToolTests(of: NSTextField.self).map(\.stringValue).joined(separator: "\n") + "\n"
            + descendantsForCommandToolTests(of: AppKitMarkdownTextView.self).map(\.string).joined(separator: "\n")
    }

    func descendantsForCommandToolTests<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendantsForCommandToolTests(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
