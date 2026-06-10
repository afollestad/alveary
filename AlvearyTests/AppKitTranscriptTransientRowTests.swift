@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptTransientRowTests: XCTestCase {
    func testStreamingBubbleInvalidatesHeightWhenTextGrows() {
        let row = AppKitTranscriptStreamingBubbleView()
        var invalidationCount = 0
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        row.frame = NSRect(x: 0, y: 0, width: 260, height: 400)
        row.configure(.init(text: "Short", bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()
        let initialHeight = row.intrinsicContentSize.height

        row.configure(.init(text: String(repeating: "Streaming content wraps ", count: 30), bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(invalidationCount, 1)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, initialHeight)
    }

    func testStreamingBubbleUsesTranscriptTypography() throws {
        var settings = AppSettings()
        settings.chatFontSize = 18
        let typography = TranscriptTypography(settings: settings)
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 260, height: 200)

        row.configure(.init(text: "Streaming", bubbleMaxWidth: 220, typography: typography))
        row.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        XCTAssertEqual(textField.font?.pointSize, 18)
    }

    func testStreamingBubbleChromeHugsShortTextBeforeMaxWidth() throws {
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

        row.configure(.init(text: "Short", bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()

        let bubbleView = try XCTUnwrap(row.subviews.first)
        XCTAssertLessThan(bubbleView.frame.width, 120)
    }

    func testStreamingBubblePinsTextToTopPaddingWhileGrowing() throws {
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 320, height: 400)

        row.configure(.init(text: "Short", bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()
        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        let initialTextY = textField.frame.minY

        row.configure(.init(text: String(repeating: "Streaming content wraps ", count: 30), bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()

        let bubbleView = try XCTUnwrap(row.subviews.first)
        XCTAssertTrue(bubbleView.isFlipped)
        XCTAssertEqual(textField.frame.minY, initialTextY, accuracy: 0.5)
        XCTAssertEqual(textField.frame.minY, chatVerticalPadding, accuracy: 0.5)
    }

    func testStreamingBubbleRevealKeepsLayoutMonotonicAfterInitialRender() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [], backing: .buffered, defer: false)
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(row)

        row.configure(.init(text: "Short", bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()
        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        let initialHeight = row.intrinsicContentSize.height
        var previousDisplayedCount = row.displayedTextForTesting.count

        row.configure(.init(text: "Short " + String(repeating: "Streaming content wraps ", count: 18), bubbleMaxWidth: 220))
        for _ in 0..<20 where row.intrinsicContentSize.height <= initialHeight {
            row.advanceStreamingRevealForTesting()
            row.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(row.displayedTextForTesting.count, previousDisplayedCount)
            XCTAssertEqual(textField.frame.minY, chatVerticalPadding, accuracy: 0.5)
            previousDisplayedCount = row.displayedTextForTesting.count
        }

        XCTAssertGreaterThan(row.intrinsicContentSize.height, initialHeight)
    }

    func testStreamingBubbleRevealsAppendedTextInStepsWhenAttachedToWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [], backing: .buffered, defer: false)
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(row)

        row.configure(.init(text: "Short", bubbleMaxWidth: 220))
        row.layoutSubtreeIfNeeded()

        let longText = "Short " + String(repeating: "Streaming content wraps ", count: 18)
        row.configure(.init(text: longText, bubbleMaxWidth: 220))

        XCTAssertEqual(row.displayedTextForTesting, "Short")

        row.advanceStreamingRevealForTesting()
        XCTAssertGreaterThan(row.displayedTextForTesting.count, "Short".count)
        XCTAssertLessThan(row.displayedTextForTesting.count, longText.count)

        for _ in 0..<80 where row.displayedTextForTesting != longText {
            row.advanceStreamingRevealForTesting()
        }
        XCTAssertEqual(row.displayedTextForTesting, longText)
    }

    func testStreamingBubbleIgnoresStaleShorterPartialText() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [], backing: .buffered, defer: false)
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(row)

        row.configure(.init(text: "Streaming response keeps growing forward", bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        row.configure(.init(text: "Streaming response", bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.displayedTextForTesting, "Streaming response keeps growing forward")
    }

    func testStreamingBubbleIgnoresStaleShorterNonPrefixPartialText() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [], backing: .buffered, defer: false)
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 240)
        window.contentView?.addSubview(row)

        row.configure(.init(text: "Streaming response keeps growing forward", bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        row.configure(.init(text: "Different stale value", bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.displayedTextForTesting, "Streaming response keeps growing forward")
    }

    func testStreamingCursorFollowsLastGlyphInsteadOfLineWidth() throws {
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 240)

        row.configure(
            .init(
                text: "This first line is intentionally long enough to wrap onto a second line short",
                bubbleMaxWidth: 220
            )
        )
        row.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        let textFrame = textField.frame
        XCTAssertGreaterThan(row.cursorFrameForTesting.minY, chatVerticalPadding)
        XCTAssertLessThan(row.cursorFrameForTesting.minX, textFrame.maxX - 20)
    }

    func testStreamingCursorUsesLineAdvanceInsteadOfLastGlyphInkBounds() throws {
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        let text = "The streaming caret should sit after this final word"

        row.configure(.init(text: text, bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        let font = try XCTUnwrap(textField.font)
        let finalInsertionPoint = finalLineInsertionPoint(for: text, font: font, width: textField.frame.width)
        XCTAssertEqual(row.cursorFrameForTesting.minX, chatBubbleHorizontalPadding + finalInsertionPoint.x + 2, accuracy: 0.5)
    }

    func testStreamingCursorFollowsTrailingSpaceInsertionPoint() throws {
        let row = AppKitTranscriptStreamingBubbleView()
        row.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        let text = "The streaming caret should preserve this trailing space "

        row.configure(.init(text: text, bubbleMaxWidth: 260))
        row.layoutSubtreeIfNeeded()

        let textField = try XCTUnwrap(row.descendants(of: NSTextField.self).first)
        let font = try XCTUnwrap(textField.font)
        let finalInsertionPoint = finalLineInsertionPoint(for: text, font: font, width: textField.frame.width)
        XCTAssertEqual(row.cursorFrameForTesting.minX, chatBubbleHorizontalPadding + finalInsertionPoint.x + 2, accuracy: 0.5)
    }

    func testThinkingIndicatorHasStableHeightAndAccessibilityLabel() {
        let row = AppKitTranscriptThinkingIndicatorView()
        row.frame = NSRect(x: 0, y: 0, width: 260, height: 200)

        row.configure(.init(bubbleMaxWidth: 220, isAnimated: false))
        row.layoutSubtreeIfNeeded()

        XCTAssertEqual(row.intrinsicContentSize.height, 7 + (chatVerticalPadding * 2), accuracy: 0.5)
        XCTAssertEqual(row.accessibilityLabel(), "Assistant is thinking")
    }

    func testThinkingIndicatorOffsetsDotsFromRowLeadingEdge() throws {
        let row = AppKitTranscriptThinkingIndicatorView()
        row.frame = NSRect(x: 0, y: 0, width: 260, height: 80)

        row.configure(.init(bubbleMaxWidth: 220, isAnimated: false))
        row.layoutSubtreeIfNeeded()

        let firstDotFrame = try XCTUnwrap(row.dotFramesForTesting.first)
        XCTAssertEqual(firstDotFrame.minX, 10, accuracy: 0.5)
    }

    func testThinkingIndicatorAnimatesWhenAttachedToWindow() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 80), styleMask: [], backing: .buffered, defer: false)
        let row = AppKitTranscriptThinkingIndicatorView()
        row.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 260, height: 80)

        window.contentView?.addSubview(row)
        row.configure(.init(bubbleMaxWidth: 220, isAnimated: true))
        row.layoutSubtreeIfNeeded()

        let dots = row.descendants(of: AppKitDynamicColorView.self)
        XCTAssertEqual(dots.count, 3)
        XCTAssertTrue(dots.allSatisfy { $0.layer?.animation(forKey: "opacity") != nil })
        XCTAssertTrue(dots.allSatisfy { $0.layer?.animation(forKey: "transform.scale") != nil })
    }
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

private func finalLineInsertionPoint(for text: String, font: NSFont, width: CGFloat) -> CGPoint {
    let textStorage = NSTextStorage(string: text + "\u{200B}", attributes: [.font: font])
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 0
    textContainer.lineBreakMode = .byWordWrapping
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: textContainer)

    let glyphIndex = layoutManager.glyphIndexForCharacter(at: textStorage.length - 1)
    let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
    let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    return CGPoint(x: glyphLocation.x, y: lineRect.minY)
}
