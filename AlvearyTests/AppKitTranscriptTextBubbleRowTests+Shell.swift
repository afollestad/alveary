@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testUnchangedAssistantBubbleConfigurationDoesNotInvalidateHeight() {
        let row = AppKitTranscriptTextBubbleRowView()
        let configuration = AppKitTranscriptTextBubbleRowView.Configuration(
            role: .assistant,
            markdown: "Short message",
            bubbleMaxWidth: 320
        )
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        row.configure(configuration)
        row.layoutSubtreeIfNeeded()

        var invalidationCount = 0
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        row.configure(configuration)
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(invalidationCount, 0)
    }

    func testReservedMarkdownHeightMatchesHydratedMarkdownHeight() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 760, height: 1_000)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                Here is the current status:

                | File | State |
                | :--- | :--- |
                | `AppKitTranscriptScrollContainerView.swift` | Done |

                ```swift
                let followsBottom = true
                ```
                """,
                bubbleMaxWidth: 560
            )
        )
        row.layoutSubtreeIfNeeded()

        let markdownFrame = try XCTUnwrap(row.markdownFrameForTesting)
        let hydratedHeight = try XCTUnwrap(row.markdownIntrinsicHeightForTesting)

        XCTAssertEqual(markdownFrame.height, hydratedHeight, accuracy: 0.5)
        XCTAssertEqual(row.intrinsicContentSize.height, row.bubbleFrameForTesting.height, accuracy: 0.5)
    }

    func testReservedMarkdownSlotFrameMatchesBubblePadding() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 500)
        row.configure(
            .init(role: .assistant, markdown: "Body with `code`.", bubbleMaxWidth: 420)
        )
        row.layoutSubtreeIfNeeded()

        let markdownFrame = try XCTUnwrap(row.markdownFrameForTesting)

        XCTAssertEqual(row.markdownClipFrameForTesting.minX, chatBubbleHorizontalPadding, accuracy: 0.5)
        XCTAssertEqual(row.markdownClipFrameForTesting.minY, chatVerticalPadding, accuracy: 0.5)
        XCTAssertEqual(markdownFrame.width, row.markdownClipFrameForTesting.width, accuracy: 0.5)
    }
}
