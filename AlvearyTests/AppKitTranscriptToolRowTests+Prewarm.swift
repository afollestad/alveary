@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testPrewarmedCollapsedToolDetailsStayHiddenUntilExpansion() async throws {
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
        let headerView = try XCTUnwrap(row.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        let detailsView = try XCTUnwrap(row.descendants(of: AppKitTranscriptToolDetailsView.self).first)
        XCTAssertGreaterThan(detailsView.frame.minY, headerView.frame.maxY)
        XCTAssertEqual(detailsView.frame.minX, transcriptInlineToolRowMetrics(for: TranscriptTypography()).detailLeadingInset, accuracy: 0.5)
    }

    func testExpandedToolDetailsClipToAnimatedRowBounds() throws {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        row.configure(.init(tool: prewarmTool(output: (1...20).map { "line \($0)" }.joined(separator: "\n"))))
        row.layoutSubtreeIfNeeded()
        let collapsedHeight = row.intrinsicContentSize.height

        row.setExpanded(true)
        row.layoutSubtreeIfNeeded()
        let detailsView = try XCTUnwrap(row.descendants(of: AppKitTranscriptToolDetailsView.self).first)
        row.frame.size.height = collapsedHeight

        XCTAssertTrue(row.clipsToBounds)
        XCTAssertGreaterThan(detailsView.frame.maxY, row.bounds.maxY)
    }
}

private func prewarmTool(output: String = "line 1") -> ToolEntry {
    ToolEntry(
        id: "tool-1",
        name: "CustomTool",
        summary: "Running `swift test`",
        input: #"{"command":"swift test"}"#,
        output: output,
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
