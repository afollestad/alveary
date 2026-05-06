@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptTextBubbleRowTests: XCTestCase {
    func testAssistantBubbleInvalidatesHeightWhenMarkdownChanges() {
        let row = AppKitTranscriptTextBubbleRowView()
        var invalidationCount = 0
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 1_000)
        row.configure(
            .init(role: .assistant, markdown: "Short message", bubbleMaxWidth: 320)
        )
        row.layoutSubtreeIfNeeded()
        let initialHeight = row.intrinsicContentSize.height

        row.configure(
            .init(
                role: .assistant,
                markdown: (0..<24).map { "Wrapped assistant line \($0)" }.joined(separator: "\n\n"),
                bubbleMaxWidth: 320
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(invalidationCount, 1)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, initialHeight)
    }

    func testShortAssistantBubbleStaysCompact() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        row.configure(
            .init(role: .assistant, markdown: "Short message", bubbleMaxWidth: 320)
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertLessThan(row.intrinsicContentSize.height, 80)
        XCTAssertLessThan(row.bubbleFrameForTesting.width, 180)
    }

    func testAssistantBubbleRefreshesCachedLayerColorWhenAppearanceChanges() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.appearance = NSAppearance(named: .darkAqua)
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        row.configure(
            .init(role: .assistant, markdown: "Short message", bubbleMaxWidth: 320)
        )
        row.layoutSubtreeIfNeeded()
        let darkBackground = try XCTUnwrap(row.bubbleBackgroundColorForTesting)

        row.appearance = NSAppearance(named: .aqua)
        row.viewDidChangeEffectiveAppearance()
        let lightBackground = try XCTUnwrap(row.bubbleBackgroundColorForTesting)

        XCTAssertNotEqual(darkBackground, lightBackground)
        XCTAssertEqual(
            lightBackground,
            NSColor.secondaryLabelColor.resolved(for: NSAppearance(named: .aqua)!).withAlphaComponent(0.08).cgColor
        )
    }

    func testAssistantBubbleGrowsOnlyToConfiguredMaxWidth() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        row.configure(
            .init(role: .assistant, markdown: String(repeating: "Long assistant text ", count: 30), bubbleMaxWidth: 320)
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.bubbleFrameForTesting.width, 320, accuracy: 1)
    }

    func testWideTableBubbleUsesConfiguredMaxWidth() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                | Name | Color | Animal | Food | City | Sport | Season | Music |
                | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
                | Alice | Red | Cat | Pizza | Paris | Tennis | Summer | Jazz |
                """,
                bubbleMaxWidth: 700
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.bubbleFrameForTesting.width, 700, accuracy: 1)
    }

    func testWideCodeBubbleUsesConfiguredMaxWidth() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                ```swift
                let value = "\(String(repeating: "wide ", count: 80))"
                ```
                """,
                bubbleMaxWidth: 420
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.bubbleFrameForTesting.width, 420, accuracy: 1)
    }

    func testShortCodeBubbleHugsNaturalWidth() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                ```swift
                let followsBottom = true
                ```
                """,
                bubbleMaxWidth: 700
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertLessThan(row.bubbleFrameForTesting.width, 700)
    }

    func testNarrowTableBubbleHugsTableWidth() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                | Name | Color |
                | :--- | :--- |
                | Alice | Red |
                """,
                bubbleMaxWidth: 700
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertLessThan(row.bubbleFrameForTesting.width, 320)
    }

    func testAssistantBubbleInvalidatesHeightWhenWidthChanges() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        row.configure(
            .init(
                role: .assistant,
                markdown: String(repeating: "wrapping text ", count: 80),
                bubbleMaxWidth: 480
            )
        )
        row.layoutSubtreeIfNeeded()
        let wideHeight = row.intrinsicContentSize.height

        var invalidatedAfterResize = false
        row.onHeightInvalidated = {
            invalidatedAfterResize = true
        }
        row.frame = NSRect(x: 0, y: 0, width: 220, height: 1_000)
        row.needsLayout = true
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidatedAfterResize)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, wideHeight)
    }

    func testAssistantBubbleMeasurementDoesNotStretchMarkdownToProbeHeight() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 760, height: 4_000)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                Found the issue:

                1. The row should measure its content height.
                2. The temporary probe frame should not stretch the markdown stack.
                3. The bubble should remain close to the rendered text.
                """,
                bubbleMaxWidth: 700
            )
        )
        row.layoutSubtreeIfNeeded()

        let markdownView = try XCTUnwrap(row.descendants(of: AppKitMarkdownView.self).first)
        XCTAssertLessThan(row.intrinsicContentSize.height, 260)
        XCTAssertLessThan(markdownView.frame.height, 230)
    }

    func testShortMarkdownListDoesNotShowExpansionControl() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 500)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                **Bold**, *italic*, [Link](https://example.com)

                Ordered

                1. Hello
                2. World
                3. Test

                Unordered

                - Hello
                - World
                - Test
                """,
                bubbleMaxWidth: 320
            )
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertTrue(row.isExpansionButtonHiddenForTesting)
        XCTAssertFalse(row.hasCollapsedFadeMaskForTesting)
        XCTAssertEqual(row.expansionButtonFrameForTesting, .zero)
    }

    func testLongAssistantBubbleCollapsesAndExpands() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        var expansionChange: Bool?
        row.onExpansionChanged = { expansionChange = $0 }
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
        let collapsedHeight = row.intrinsicContentSize.height
        XCTAssertTrue(row.hasCollapsedFadeMaskForTesting)
        XCTAssertEqual(row.collapsedFadeMaskDirectionForTesting.start, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(row.collapsedFadeMaskDirectionForTesting.end, CGPoint(x: 0.5, y: 1))

        let showMore = try XCTUnwrap(row.descendants(of: NSButton.self).first { $0.title == "Show more" })
        let showMoreToggle = try XCTUnwrap(showMore as? AppKitTranscriptHeaderToggleButton)
        XCTAssertEqual(showMoreToggle.symbolNameForTesting, "chevron.down")
        let showMoreIconSize = try XCTUnwrap(showMoreToggle.symbolDrawingSizeForTesting)
        XCTAssertGreaterThan(showMoreIconSize.width, showMoreIconSize.height)
        XCTAssertEqual(
            row.bubbleFrameForTesting.maxY - row.expansionButtonFrameForTesting.maxY,
            chatVerticalPadding,
            accuracy: 1
        )
        showMore.performClick(nil)
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(expansionChange, true)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, collapsedHeight)
        XCTAssertFalse(row.hasCollapsedFadeMaskForTesting)
        let showLess = try XCTUnwrap(row.descendants(of: NSButton.self).first { $0.title == "Show less" } as? AppKitTranscriptHeaderToggleButton)
        XCTAssertEqual(showLess.symbolNameForTesting, "chevron.up")
        let showLessIconSize = try XCTUnwrap(showLess.symbolDrawingSizeForTesting)
        XCTAssertGreaterThan(showLessIconSize.width, showLessIconSize.height)
    }

    func testUserBubbleUsesComposerChipsAndUserInlineCodeStyle() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(role: .user, markdown: "Review @/tmp/My%20File.swift and `pwd`.")
        )
        row.layoutSubtreeIfNeeded()

        let textViews = row.descendants(of: AppKitMarkdownTextView.self)
        XCTAssertTrue(textViews.map(\.string).contains { $0.contains("@My File.swift") })
        let rendered = textViews.first?.textStorage?.string ?? ""
        let mentionRange = (rendered as NSString).range(of: "@My File.swift")
        XCTAssertNotEqual(mentionRange.location, NSNotFound)
        XCTAssertEqual(
            textViews.first?.textStorage?.attribute(.backgroundColor, at: mentionRange.location, effectiveRange: nil) as? NSColor,
            AppMarkdownCodeBlockPalette.userBubbleInlineFillNSColor
        )
        XCTAssertEqual(
            textViews.first?.textStorage?.attribute(.foregroundColor, at: mentionRange.location, effectiveRange: nil) as? NSColor,
            AppMarkdownCodeBlockPalette.inlineChipForegroundNSColor
        )
        XCTAssertNil(textViews.first?.textStorage?.attribute(.underlineStyle, at: mentionRange.location, effectiveRange: nil))
    }

    func testShortUserBubbleHugsContentAndStaysRightAligned() {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        row.configure(
            .init(role: .user, markdown: "Short user message.")
        )
        row.layoutSubtreeIfNeeded()

        XCTAssertLessThan(row.bubbleFrameForTesting.width, 220)
        XCTAssertEqual(row.bubbleFrameForTesting.maxX, row.bounds.maxX, accuracy: 1)
    }

    func testUserBubbleShowsRetryFooterAndInvokesCallback() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        var didRetry = false
        row.onRetry = {
            didRetry = true
        }
        var settings = AppSettings()
        settings.chatFontSize = 18
        let typography = TranscriptTypography(settings: settings).appKitMarkdownTypography
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(role: .user, markdown: "Failed send", typography: typography, showsRetry: true)
        )
        row.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(row.descendants(of: NSButton.self).first { $0.title == "Retry" })
        let status = try XCTUnwrap(row.descendants(of: NSTextField.self).first { $0.stringValue == "Not sent" })

        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(status.font?.pointSize, 16)
        XCTAssertGreaterThanOrEqual(row.intrinsicContentSize.height, button.frame.maxY)

        button.performClick(nil)
        XCTAssertTrue(didRetry)
    }

    func testBubbleAppliesTranscriptTypography() {
        var settings = AppSettings()
        settings.chatFontSize = 19
        settings.codeFontSize = 15
        let typography = TranscriptTypography(settings: settings).appKitMarkdownTypography
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(role: .assistant, markdown: "Body with `code`.", typography: typography)
        )
        row.layoutSubtreeIfNeeded()

        guard let textStorage = row.descendants(of: AppKitMarkdownTextView.self).first?.textStorage else {
            return XCTFail("Expected bubble to contain markdown text")
        }
        let bodyRange = (textStorage.string as NSString).range(of: "Body")
        let codeRange = (textStorage.string as NSString).range(of: "code")

        XCTAssertEqual((textStorage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont)?.pointSize, 19)
        XCTAssertEqual((textStorage.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)?.pointSize, 15)
    }

    func testBubbleReconfiguresCodeFontWhenTypographyChanges() throws {
        var smallSettings = AppSettings()
        smallSettings.codeFontSize = 11
        var largeSettings = AppSettings()
        largeSettings.codeFontSize = 21
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(
                role: .assistant,
                markdown: """
                ```swift
                let value = 1
                ```
                """,
                typography: TranscriptTypography(settings: smallSettings).appKitMarkdownTypography
            )
        )
        row.layoutSubtreeIfNeeded()

        row.configure(
            .init(
                role: .assistant,
                markdown: """
                ```swift
                let value = 1
                ```
                """,
                typography: TranscriptTypography(settings: largeSettings).appKitMarkdownTypography
            )
        )
        row.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(
            row.descendants(of: AppKitMarkdownTextView.self).first { $0.string.contains("let value") }?.textStorage
        )
        let range = (textStorage.string as NSString).range(of: "let")
        XCTAssertEqual((textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize, 21)
    }

    func testBubbleForwardsMarkdownLinkClicks() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        var openedURL: URL?
        row.onOpenMarkdownLink = { openedURL = $0 }
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(role: .assistant, markdown: "See [docs](README.md).")
        )
        row.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(row.descendants(of: AppKitMarkdownTextView.self).first)
        let link = try XCTUnwrap(linkAttribute(in: textView, matching: "docs"))

        XCTAssertTrue(textView.textView(textView, clickedOnLink: link, at: 0))
        XCTAssertEqual(openedURL?.relativeString, "README.md")
    }

    func testAssistantBubbleStylesFileReferenceLinksNeutrally() throws {
        let row = AppKitTranscriptTextBubbleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        row.configure(
            .init(role: .assistant, markdown: "See [watermark skill](.agents/skills/watermark/SKILL.md).")
        )
        row.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(row.descendants(of: AppKitMarkdownTextView.self).first?.textStorage)
        let range = (textStorage.string as NSString).range(of: "watermark skill")

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor, .labelColor)
        XCTAssertNotNil(textStorage.attribute(.link, at: range.location, effectiveRange: nil))
    }
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
