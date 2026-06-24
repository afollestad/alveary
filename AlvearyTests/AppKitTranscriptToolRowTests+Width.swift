@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptToolRowTests {
    func testHeaderMiddleTruncatesLongSummaryText() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        header.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        header.configure(
            .init(
                summary: "Reading \(longScreenshotPath)",
                leadingIcon: .document,
                phase: .loading
            )
        )
        header.layoutSubtreeIfNeeded()

        let summaryField = try XCTUnwrap(header.descendants(of: NSTextField.self).first)
        XCTAssertEqual(summaryField.lineBreakMode, .byTruncatingMiddle)
        XCTAssertEqual(summaryField.maximumNumberOfLines, 1)
    }

    func testInlineToolRowClampsVisibleContentToMaxWidth() throws {
        let row = AppKitTranscriptInlineToolRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 1_000)
        row.configure(
            .init(
                tool: widthTool(name: "Read", summary: "Reading \(longScreenshotPath)"),
                maxWidth: 360
            )
        )
        row.layoutSubtreeIfNeeded()

        let clipView = try XCTUnwrap(row.descendants(of: AppKitTranscriptExpandableClipView.self).first)
        let header = try XCTUnwrap(row.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertEqual(clipView.frame.width, 360, accuracy: 0.5)
        XCTAssertEqual(header.frame.width, 360, accuracy: 0.5)
    }

    func testHeaderStatusFollowsCompactedLongAttributedSummaryWidth() throws {
        let header = AppKitTranscriptToolHeaderRowView()
        let width: CGFloat = 1_000
        header.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        header.configure(
            .init(
                summary: "Read `\(longSnapshotPath)`",
                leadingIcon: .book,
                phase: .success
            )
        )
        header.layoutSubtreeIfNeeded()

        let metrics = transcriptInlineToolRowMetrics(for: TranscriptTypography())
        let summaryField = try XCTUnwrap(header.descendants(of: NSTextField.self).first)
        let statusView = try XCTUnwrap(header.descendants(of: AppKitTranscriptToolStatusIndicatorView.self).first)
        let maxSummaryWidth = width - metrics.leadingTextInset - metrics.textStatusSpacing - metrics.controlSize

        XCTAssertGreaterThan(summaryField.fittingSize.width, maxSummaryWidth)
        XCTAssertLessThan(summaryField.frame.width, maxSummaryWidth - 40)
        XCTAssertEqual(statusView.frame.minX, summaryField.frame.maxX + metrics.textStatusSpacing - 4, accuracy: 0.5)
        XCTAssertLessThan(statusView.frame.minX, width - metrics.controlSize - 40)
    }

    func testToolGroupClampsVisibleContentToMaxWidth() throws {
        let group = AppKitTranscriptToolGroupView()
        group.frame = NSRect(x: 0, y: 0, width: 900, height: 1_000)
        group.configure(
            .init(
                tools: [
                    widthTool(id: "read-1", name: "Read", summary: "Reading \(longScreenshotPath)"),
                    widthTool(id: "grep-1", name: "Grep", summary: "Searching for AppKit")
                ],
                maxWidth: 360
            )
        )
        group.layoutSubtreeIfNeeded()

        let clipView = try XCTUnwrap(group.descendants(of: AppKitTranscriptExpandableClipView.self).first)
        let header = try XCTUnwrap(group.descendants(of: AppKitTranscriptToolHeaderRowView.self).first)
        XCTAssertEqual(clipView.frame.width, 360, accuracy: 0.5)
        XCTAssertEqual(header.frame.width, 360, accuracy: 0.5)
    }
}

private let longScreenshotPath = "/var/folders/q3/fgp9x7g90_j_8ln525h_5hyw0000gn/" +
    "T/TemporaryItems/NSIRD_screencaptureui/Screenshot.png"

private let longSnapshotPath = "/Users/afollestad/Development/alveary/AlvearyTests/Snapshots/__Snapshots__/" +
    "SnapshotTests+AppKitTranscript/testAppKitTranscriptAssistantMarkdownBubble.appkit_transcript_assistant_markdown_bubble.png"

private func widthTool(id: String = "tool-1", name: String, summary: String) -> ToolEntry {
    ToolEntry(
        id: id,
        name: name,
        summary: summary,
        input: #"{"path":"AGENTS.md"}"#,
        output: nil,
        stderr: nil,
        isComplete: false,
        isInterrupted: false,
        isImage: false,
        noOutputExpected: false,
        isError: false
    )
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
