@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptToolDetailViewTests: XCTestCase {
    func testDetailCodeBlockInvalidatesHeightWhenContentChanges() {
        let block = AppKitTranscriptDetailCodeBlockView()
        var invalidationCount = 0
        block.onHeightInvalidated = {
            invalidationCount += 1
        }
        block.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        block.configure(.init(title: "Input", content: "short"))
        block.layoutSubtreeIfNeeded()
        let initialHeight = block.intrinsicContentSize.height

        block.configure(
            .init(title: "Input", content: (0..<30).map { "line \($0)" }.joined(separator: "\n"))
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(invalidationCount, 1)
        XCTAssertGreaterThan(block.intrinsicContentSize.height, initialHeight)
    }

    func testHighlightedCodeBlockAppliesTranscriptCodeTypography() {
        var settings = AppSettings()
        settings.codeFontFamily = "Monaco"
        settings.codeFontSize = 17
        let typography = TranscriptTypography(settings: settings)
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)

        block.configure(
            .init(content: "let value = 1", language: "swift", typography: typography)
        )
        block.layoutSubtreeIfNeeded()

        guard let textStorage = block.descendants(of: AppKitMarkdownTextView.self).first?.textStorage else {
            return XCTFail("Expected highlighted block text storage")
        }
        XCTAssertEqual((textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 17)
    }

    func testHighlightedCodeBlockReconfiguresWhenCodeTypographyChanges() throws {
        var smallSettings = AppSettings()
        smallSettings.codeFontSize = 11
        var largeSettings = AppSettings()
        largeSettings.codeFontSize = 22
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)

        block.configure(
            .init(content: "let value = 1", language: "swift", typography: TranscriptTypography(settings: smallSettings))
        )
        block.layoutSubtreeIfNeeded()
        block.configure(
            .init(content: "let value = 1", language: "swift", typography: TranscriptTypography(settings: largeSettings))
        )
        block.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(block.descendants(of: AppKitMarkdownTextView.self).first?.textStorage)
        XCTAssertEqual((textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 22)
    }

    func testHighlightedCodeBlockAppliesAppKitSyntaxColors() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.appearance = NSAppearance(named: .darkAqua)
        block.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)

        block.configure(.init(content: "function applyTheme() { return true; }", language: "javascript"))
        block.layoutSubtreeIfNeeded()

        let textStorage = try XCTUnwrap(block.descendants(of: AppKitMarkdownTextView.self).first?.textStorage)
        let keywordRange = (textStorage.string as NSString).range(of: "function")
        let keywordColor = try XCTUnwrap(textStorage.attribute(.foregroundColor, at: keywordRange.location, effectiveRange: nil) as? NSColor)

        XCTAssertNotEqual(keywordColor, NSColor.labelColor)
    }

    func testHighlightedCodeBlockKeepsLongLinesHorizontallyScrollable() {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 180, height: 1_000)

        block.configure(
            .init(content: "let value = \"\(String(repeating: "wide", count: 80))\"", language: "swift")
        )
        block.layoutSubtreeIfNeeded()

        guard let scrollView = block.descendants(of: NSScrollView.self).first else {
            return XCTFail("Expected highlighted block scroll view")
        }
        XCTAssertGreaterThan(scrollView.documentView?.frame.width ?? 0, scrollView.contentView.bounds.width)
    }

    func testHighlightedCodeBlockKeepsOverflowWithoutReservedScrollbarSpace() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 180, height: 1_000)

        block.configure(
            .init(content: "1  \(String(repeating: "wide", count: 80))", language: "text")
        )
        block.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(block.descendants(of: AppKitMarkdownTextView.self).first)
        let scrollView = try XCTUnwrap(block.descendants(of: NSScrollView.self).first)

        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertGreaterThan(scrollView.documentView?.frame.width ?? 0, scrollView.contentView.bounds.width)
        XCTAssertEqual(block.intrinsicContentSize.height, textView.frame.height, accuracy: 0.5)
    }

    func testHighlightedCodeBlockClampsHorizontalScrollWhenWidened() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 180, height: 1_000)
        block.configure(
            .init(content: "let value = \"\(String(repeating: "wide", count: 24))\"", language: "swift")
        )
        block.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(block.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        let initialMaxX = max((scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width, 0)
        XCTAssertGreaterThan(initialMaxX, 0)
        scrollView.contentView.scroll(to: NSPoint(x: initialMaxX, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)

        block.frame = NSRect(x: 0, y: 0, width: 900, height: 1_000)
        block.layoutSubtreeIfNeeded()

        let maxX = max((scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width, 0)
        XCTAssertLessThanOrEqual(scrollView.contentView.bounds.origin.x, maxX + 0.5)
        if maxX < 0.5 {
            XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
        }
    }

    func testHighlightedCodeBlockDoesNotMeasureTrailingBlankLines() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 220, height: 1_000)

        block.configure(.init(content: "line 1\nline 2\n   \n\t\n", language: "text"))
        block.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(block.descendants(of: AppKitMarkdownTextView.self).first)

        XCTAssertEqual(textView.string, "line 1\nline 2")
    }

    func testToolOutputDoesNotRenderTrailingBlankLines() throws {
        let view = AppKitTranscriptToolOutputView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)

        view.configure(.init(toolName: "Bash", content: "line 1\nline 2\n   \n\t\n"))
        view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(view.descendants(of: AppKitMarkdownTextView.self).first)

        XCTAssertEqual(textView.string, "line 1\nline 2")
    }

    func testToolOutputPagingIgnoresTrailingBlankLines() {
        let output = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n   \n\t\n"
        let view = AppKitTranscriptToolOutputView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)

        view.configure(.init(toolName: "Bash", content: output))
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output"))
        XCTAssertFalse(view.renderedText.contains("showing last"))
        XCTAssertFalse(view.renderedText.contains("10 /"))
    }

    func testToolOutputPagingReportsUserHeightChangeBeforeInvalidation() {
        let output = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let view = AppKitTranscriptToolOutputView()
        var events: [String] = []
        view.onUserInitiatedHeightChange = { events.append("user") }
        view.onHeightInvalidated = { events.append("height") }
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(toolName: "Bash", content: output))
        view.layoutSubtreeIfNeeded()
        events = []

        view.showMore()

        XCTAssertEqual(Array(events.prefix(2)), ["user", "height"])
    }

    func testHighlightedCodeBlockForwardsVerticalScrollToAncestor() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 180, height: 400)
        block.configure(
            .init(content: "let value = \"\(String(repeating: "wide", count: 80))\"", language: "swift")
        )

        let parentScrollView = RecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 500))
        parentScrollView.documentView = document
        document.addSubview(block)
        block.layoutSubtreeIfNeeded()

        let childScrollView = try XCTUnwrap(block.descendants(of: NSScrollView.self).first)
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: -12,
            wheel2: 0,
            wheel3: 0
        ))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        childScrollView.scrollWheel(with: event)

        XCTAssertTrue(parentScrollView.didReceiveVerticalScroll)
    }

    func testHighlightedCodeBlockDisablesVerticalElasticity() throws {
        let block = AppKitTranscriptHighlightedCodeBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 180, height: 400)
        block.configure(
            .init(content: "let value = \"\(String(repeating: "wide", count: 80))\"", language: "swift")
        )
        block.layoutSubtreeIfNeeded()

        let childScrollView = try XCTUnwrap(block.descendants(of: AppKitHorizontalOverflowScrollView.self).first)

        XCTAssertEqual(childScrollView.verticalScrollElasticity, .none)
    }

    func testToolOutputStartsWithBashTailAndShowsMoreFromTop() {
        let output = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let view = AppKitTranscriptToolOutputView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(toolName: "Bash", content: output))
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output (showing last 10 of 30 lines)"))
        XCTAssertFalse(view.renderedText.contains("line 10"))
        XCTAssertTrue(view.renderedText.contains("line 30"))

        view.showMore()
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output (showing last 20 of 30 lines)"))
        XCTAssertTrue(view.renderedText.contains("line 11"))
        XCTAssertFalse(view.renderedText.contains("line 10"))
    }

    func testToolOutputStartsWithCommandExecutionTailAndPreservesPagingWindow() {
        let view = AppKitTranscriptToolOutputView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(toolName: "CommandExecution", content: (1...30).map { "line \($0)" }.joined(separator: "\n")))
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output (showing last 10 of 30 lines)"))
        XCTAssertFalse(view.renderedText.contains("line 20"))
        XCTAssertTrue(view.renderedText.contains("line 30"))

        view.showMore()
        view.layoutSubtreeIfNeeded()
        view.configure(.init(toolName: "CommandExecution", content: (1...31).map { "line \($0)" }.joined(separator: "\n")))
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output (showing last 20 of 31 lines)"))
        XCTAssertTrue(view.renderedText.contains("line 12"))
        XCTAssertFalse(view.renderedText.contains("line 11"))
    }

    func testToolOutputInvalidatesHeightWhenPagedOutputExpands() {
        let output = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let view = AppKitTranscriptToolOutputView()
        var invalidated = false
        view.onHeightInvalidated = {
            invalidated = true
        }
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(toolName: "Read", content: output))
        view.layoutSubtreeIfNeeded()
        let initialHeight = view.intrinsicContentSize.height
        invalidated = false

        view.showMore()
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, initialHeight)
    }

    func testToolOutputPreservesPagingWindowWhenContentUpdates() {
        let view = AppKitTranscriptToolOutputView()
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 1_000)
        view.configure(.init(toolName: "Bash", content: (1...30).map { "line \($0)" }.joined(separator: "\n")))
        view.layoutSubtreeIfNeeded()
        view.showMore()
        view.layoutSubtreeIfNeeded()

        view.configure(.init(toolName: "Bash", content: (1...31).map { "line \($0)" }.joined(separator: "\n")))
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.renderedText.contains("Output (showing last 20 of 31 lines)"))
        XCTAssertTrue(view.renderedText.contains("line 12"))
        XCTAssertFalse(view.renderedText.contains("line 11"))
    }
}

private final class RecordingScrollView: NSScrollView {
    var didReceiveVerticalScroll = false

    override func scrollWheel(with event: NSEvent) {
        didReceiveVerticalScroll = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
    }
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
