@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitMarkdownRendererTests {
    func testParagraphTextViewForwardsVerticalScrollToAncestor() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: String(repeating: "scrollable text ", count: 20)
        )
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 220, height: 200)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(view)
        view.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(view.descendants(of: AppKitMarkdownTextView.self).first)
        textView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: 0))

        XCTAssertTrue(parentScrollView.didReceiveVerticalScroll)
    }

    func testCodeBlockTextViewKeepsHorizontalScrollLocal() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(codeBlock)
        let window = try Self.mountScrollView(parentScrollView)
        defer { window.contentView = nil; window.close() }
        parentScrollView.layoutSubtreeIfNeeded()
        codeBlock.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(codeBlock.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        let textView = try XCTUnwrap(codeBlock.descendants(of: AppKitMarkdownTextView.self).first)
        let document = try XCTUnwrap(overflowScrollView.documentView)
        XCTAssertGreaterThan(document.frame.width - overflowScrollView.contentView.bounds.width, 160)
        overflowScrollView.contentView.scroll(to: NSPoint(x: 80, y: 0))
        overflowScrollView.reflectScrolledClipView(overflowScrollView.contentView)
        let initialX = overflowScrollView.contentView.bounds.minX
        XCTAssertEqual(initialX, 80, accuracy: 0.5)
        textView.scrollWheel(with: try Self.scrollEvent(deltaY: 0, deltaX: -12))

        Self.waitForHorizontalMovement(in: overflowScrollView, from: initialX)
        XCTAssertEqual(parentScrollView.verticalScrollCount, 0)
        XCTAssertGreaterThan(overflowScrollView.contentView.bounds.minX, initialX)
    }

    func testCodeBlockTextViewForwardsPreciseVerticalScrollToAncestor() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(codeBlock)
        codeBlock.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(codeBlock.descendants(of: AppKitMarkdownTextView.self).first)
        textView.scrollWheel(with: try Self.preciseScrollEvent(deltaY: -12, deltaX: -12))

        XCTAssertTrue(parentScrollView.didReceiveVerticalScroll)
    }

    func testCodeBlockOverflowForwardsMostlyVerticalScrollToAncestor() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(codeBlock)
        codeBlock.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(codeBlock.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        overflowScrollView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: -12))

        XCTAssertTrue(parentScrollView.didReceiveVerticalScroll)
    }

    func testCodeBlockOverflowKeepsForwardingDecayingVerticalMomentum() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(codeBlock)
        codeBlock.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(codeBlock.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        overflowScrollView.scrollWheel(with: try Self.preciseScrollEvent(deltaY: -12, deltaX: -1))
        overflowScrollView.scrollWheel(with: try Self.preciseScrollEvent(deltaY: -1, deltaX: -4))

        XCTAssertEqual(parentScrollView.verticalScrollCount, 2)
    }

    func testCodeBlockOverflowDisablesVerticalElasticity() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        codeBlock.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(codeBlock.descendants(of: AppKitHorizontalOverflowScrollView.self).first)

        XCTAssertEqual(overflowScrollView.verticalScrollElasticity, .none)
    }

    func testCodeBlockOverflowKeepsHorizontalScrollLocal() throws {
        let codeBlock = AppKitMarkdownCodeBlockView(
            code: "let value = \"\(String(repeating: "wide ", count: 80))\"",
            languageHint: "swift"
        )
        codeBlock.frame = NSRect(x: 0, y: 0, width: 220, height: 120)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 400))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(codeBlock)
        let window = try Self.mountScrollView(parentScrollView)
        defer { window.contentView = nil; window.close() }
        parentScrollView.layoutSubtreeIfNeeded()
        codeBlock.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(codeBlock.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        let document = try XCTUnwrap(overflowScrollView.documentView)
        XCTAssertGreaterThan(document.frame.width - overflowScrollView.contentView.bounds.width, 160)
        overflowScrollView.contentView.scroll(to: NSPoint(x: 80, y: 0))
        overflowScrollView.reflectScrolledClipView(overflowScrollView.contentView)
        let initialX = overflowScrollView.contentView.bounds.minX
        XCTAssertEqual(initialX, 80, accuracy: 0.5)
        overflowScrollView.scrollWheel(with: try Self.scrollEvent(deltaY: -4, deltaX: -12))

        Self.waitForHorizontalMovement(in: overflowScrollView, from: initialX)
        XCTAssertEqual(parentScrollView.verticalScrollCount, 0)
        XCTAssertGreaterThan(overflowScrollView.contentView.bounds.minX, initialX)
    }

    func testTableOverflowForwardsMostlyVerticalScrollToAncestor() throws {
        let document = AppMarkdownParser().documentPreservingSource(
            for: """
            | Name | Color | Animal | Food | City | Sport | Season | Music |
            | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
            | Alice | Red | Cat | Pizza | Paris | Tennis | Summer | Jazz |
            """
        )
        let view = AppKitMarkdownView(document: document)
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(view.descendants(of: AppKitMarkdownTableView.self).first)
        let parentScrollView = MarkdownRecordingScrollView()
        parentScrollView.hasVerticalScroller = true
        let scrollDocument = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 800))
        parentScrollView.documentView = scrollDocument
        scrollDocument.addSubview(table)
        table.layoutSubtreeIfNeeded()

        let overflowScrollView = try XCTUnwrap(table.descendants(of: AppKitHorizontalOverflowScrollView.self).first)
        overflowScrollView.scrollWheel(with: try Self.scrollEvent(deltaY: -12, deltaX: -12))

        XCTAssertTrue(parentScrollView.didReceiveVerticalScroll)
    }

    private static func mountScrollView(_ scrollView: NSScrollView) throws -> NSWindow {
        let screen = try XCTUnwrap(NSScreen.main)
        // AppKit's legacy wheel path needs a display-backed frame for its animation ticks.
        // The window can remain hidden; a frame entirely outside every display never scrolls.
        let window = NSWindow(
            contentRect: NSRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.minY + 40, width: 260, height: 200),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        return window
    }

    private static func waitForHorizontalMovement(in scrollView: NSScrollView, from initialX: CGFloat) {
        // AppKit animates line-wheel events after dispatch; observe the mounted clip view's result.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while scrollView.contentView.bounds.minX <= initialX, ContinuousClock.now < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func scrollEvent(deltaY: Int32, deltaX: Int32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    private static func preciseScrollEvent(deltaY: Int32, deltaX: Int32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }
}

private final class MarkdownRecordingScrollView: NSScrollView {
    var didReceiveVerticalScroll = false
    var verticalScrollCount = 0

    override func scrollWheel(with event: NSEvent) {
        verticalScrollCount += 1
        didReceiveVerticalScroll = didReceiveVerticalScroll || abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
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
