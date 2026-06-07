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

    func testCollapsedHeightUsesTargetMetricsDuringAnimatedFrameSettle() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        row.configure(
            .init(
                id: "assistant-long",
                role: .assistant,
                markdown: (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n"),
                bubbleMaxWidth: 480
            )
        )
        row.layoutSubtreeIfNeeded()
        let initialCollapsedHeight = row.intrinsicContentSize.height

        XCTAssertEqual(row.expansionButton.title, "Show more")
        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        let expandedBubbleFrame = row.bubbleFrameForTesting
        XCTAssertGreaterThan(row.intrinsicContentSize.height, initialCollapsedHeight)

        XCTAssertEqual(row.expansionButton.title, "Show less")
        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        let collapsedHeight = row.intrinsicContentSize.height
        XCTAssertEqual(collapsedHeight, initialCollapsedHeight, accuracy: 0.5)

        row.bubbleView.frame = expandedBubbleFrame

        XCTAssertEqual(row.intrinsicContentSize.height, collapsedHeight, accuracy: 0.5)
        XCTAssertEqual(row.fittingSize.height, collapsedHeight, accuracy: 0.5)
    }

    func testCollapseInvalidationReportsCollapsedTargetBeforeLayoutPass() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        row.configure(
            .init(
                id: "assistant-long",
                role: .assistant,
                markdown: (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n"),
                bubbleMaxWidth: 480
            )
        )
        row.layoutSubtreeIfNeeded()
        let initialCollapsedHeight = row.intrinsicContentSize.height

        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()

        var invalidatedHeights: [CGFloat] = []
        row.onHeightInvalidated = {
            invalidatedHeights.append(row.intrinsicContentSize.height)
        }

        row.expansionButton.performClick(nil)

        XCTAssertEqual(invalidatedHeights.first ?? -1, initialCollapsedHeight, accuracy: 0.5)
        XCTAssertEqual(row.intrinsicContentSize.height, initialCollapsedHeight, accuracy: 0.5)
    }

    func testExpansionReportsUserHeightChangeBeforeInvalidation() {
        let row = AppKitTranscriptTextBubbleRowView()
        var events: [String] = []
        row.onUserInitiatedHeightChange = { events.append("user") }
        row.onHeightInvalidated = { events.append("height") }
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        row.configure(
            .init(
                id: "assistant-long",
                role: .assistant,
                markdown: (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n"),
                bubbleMaxWidth: 480
            )
        )
        row.layoutSubtreeIfNeeded()
        events = []

        row.expansionButton.performClick(nil)

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }

    func testExpansionStateEchoDoesNotResetCollapsedMarkdownMetrics() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        let markdown = (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n")
        func configuration(initiallyExpanded: Bool) -> AppKitTranscriptTextBubbleRowView.Configuration {
            .init(
                id: "assistant-long",
                role: .assistant,
                markdown: markdown,
                bubbleMaxWidth: 480,
                initiallyExpanded: initiallyExpanded
            )
        }

        row.configure(configuration(initiallyExpanded: false))
        row.layoutSubtreeIfNeeded()
        let initialCollapsedHeight = row.intrinsicContentSize.height

        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        row.configure(configuration(initiallyExpanded: true))
        row.layoutSubtreeIfNeeded()

        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        let collapsedHeight = row.intrinsicContentSize.height
        let markdownView = try XCTUnwrap(row.markdownView)

        XCTAssertEqual(
            row.bubbleFrameForTesting.maxY - row.expansionButtonFrameForTesting.maxY,
            chatVerticalPadding,
            accuracy: 0.5
        )

        row.configure(configuration(initiallyExpanded: false))
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.markdownView === markdownView)
        XCTAssertEqual(row.intrinsicContentSize.height, collapsedHeight, accuracy: 0.5)
        XCTAssertEqual(row.intrinsicContentSize.height, initialCollapsedHeight, accuracy: 0.5)
        XCTAssertEqual(
            row.bubbleFrameForTesting.maxY - row.expansionButtonFrameForTesting.maxY,
            chatVerticalPadding,
            accuracy: 0.5
        )
    }

    func testCollapsedExpansionStateEchoDoesNotInvalidateAlreadyAppliedState() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 2_000)
        let markdown = (0..<30).map { "Long assistant line \($0)" }.joined(separator: "\n\n")
        func configuration(initiallyExpanded: Bool) -> AppKitTranscriptTextBubbleRowView.Configuration {
            .init(
                id: "assistant-long",
                role: .assistant,
                markdown: markdown,
                bubbleMaxWidth: 480,
                initiallyExpanded: initiallyExpanded
            )
        }

        row.configure(configuration(initiallyExpanded: false))
        row.layoutSubtreeIfNeeded()
        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        row.configure(configuration(initiallyExpanded: true))
        row.layoutSubtreeIfNeeded()
        row.expansionButton.performClick(nil)
        row.layoutSubtreeIfNeeded()
        let markdownView = try XCTUnwrap(row.markdownView)

        var invalidationCount = 0
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        row.configure(configuration(initiallyExpanded: false))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(invalidationCount, 0)
        XCTAssertTrue(row.markdownView === markdownView)
        XCTAssertEqual(
            row.bubbleFrameForTesting.maxY - row.expansionButtonFrameForTesting.maxY,
            chatVerticalPadding,
            accuracy: 0.5
        )
    }
}
