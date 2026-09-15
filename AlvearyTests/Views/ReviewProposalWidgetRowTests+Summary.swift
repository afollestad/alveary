import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension ReviewProposalWidgetRowTests {
    func testAddCommentAcceptsKeyboardFocusAndOpensTheEditor() throws {
        let summary = ReviewSummaryTestFixture.summary(body: "")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = summary
        let button = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: summary) { ($0 as? NSButton)?.title == "Add comment" } as? NSButton)
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)
        let space = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ",
            isARepeat: false, keyCode: 49
        ))
        button.keyDown(with: space)
        XCTAssertTrue(summary.isEditing)
        XCTAssertEqual(summary.editor?.draft.markdown, "")
    }

    func testSummaryEditingIsLazyAndSaveFailureKeepsTheDraft() throws {
        let summary = ReviewSummaryTestFixture.summary()
        XCTAssertNil(summary.editor)
        var saves: [String] = []
        summary.onSave = { _, body in saves.append(body); return false }
        summary.beginEditing()
        let editor = try XCTUnwrap(summary.editor)
        editor.draft.replaceText("Edited\n\nComment")
        summary.save()
        XCTAssertEqual(saves, ["Edited\n\nComment"])
        XCTAssertTrue(summary.editor === editor)
        summary.cancel()
        XCTAssertNil(summary.editor)
        summary.beginEditing()
        XCTAssertEqual(summary.editor?.draft.markdown, "Original")
    }

    func testSummarySavingAndClearingUseTheProposalIdentity() throws {
        let summary = ReviewSummaryTestFixture.summary()
        var saves: [String] = []
        summary.onSave = { id, body in
            XCTAssertEqual(id, "proposal")
            saves.append(body)
            return true
        }
        summary.beginEditing()
        try XCTUnwrap(summary.editor).draft.replaceText("Saved\n\nComment")
        summary.save()
        XCTAssertNil(summary.editor)
        let clear = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: summary, matching: { ($0 as? NSButton)?.title == "Clear" }) as? NSButton)
        clear.performClick(nil)
        XCTAssertEqual(saves, ["Saved\n\nComment", ""])
    }

    func testRefreshPreservesDirtyEditorAndDisablesItsActionsWhileSubmitting() throws {
        let summary = ReviewSummaryTestFixture.summary()
        summary.beginEditing()
        let editor = try XCTUnwrap(summary.editor)
        editor.draft.replaceText("Unsaved")
        summary.configure(ReviewSummaryTestFixture.configuration(body: "External change"))
        XCTAssertTrue(summary.editor === editor)
        XCTAssertEqual(editor.draft.markdown, "Unsaved")
        summary.configure(ReviewSummaryTestFixture.configuration(body: "External change", isEditable: false))
        var saved = false
        summary.onSave = { _, _ in saved = true; return true }
        summary.save()
        summary.cancel()
        XCTAssertFalse(saved)
        XCTAssertTrue(summary.editor === editor)
    }

    func testPristineEditorAdoptsExternalBodyAndResolutionReleasesIt() async throws {
        let summary = ReviewSummaryTestFixture.summary()
        summary.beginEditing()
        summary.configure(ReviewSummaryTestFixture.configuration(body: "External change"))
        XCTAssertEqual(summary.editor?.draft.markdown, "External change")
        weak let oldEditor = summary.editor
        summary.configure(ReviewSummaryTestFixture.configuration(body: "Submitted", proposalID: nil, isEditable: false))
        XCTAssertNil(summary.editor)
        for _ in 0..<100 where oldEditor != nil { await Task.yield() }
        XCTAssertNil(oldEditor)
    }

    func testSummaryWrapsAndRetainsParagraphsAtNarrowWidths() throws {
        let body = String(repeating: "Long review comment with `code`. ", count: 6) + "\n\nSecond paragraph."
        let summary = ReviewSummaryTestFixture.summary(body: body)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 1_000))
        host.addSubview(summary)
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            summary.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        let wideHeight = summary.fittingSize.height
        host.frame.size.width = 280
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(summary.fittingSize.height, wideHeight)
        let rendered = ReviewSummaryTestFixture.text(in: summary)
        XCTAssertTrue(rendered.contains("Second paragraph."))
        XCTAssertTrue(rendered.contains("Long review comment"))
    }

    func testEditorFocusAndKeyboardShortcuts() async throws {
        let summary = ReviewSummaryTestFixture.summary()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = summary
        var saved: String?
        summary.onSave = { _, body in saved = body; return true }
        summary.beginEditing()
        let editor = try XCTUnwrap(summary.editor)
        let deadline = Date().addingTimeInterval(2)
        while !(window.firstResponder is NSTextView), Date() < deadline {
            window.displayIfNeeded()
            await Task.yield()
        }
        let text = try XCTUnwrap(window.firstResponder as? NSTextView)
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.insertNewline(nil)
        XCTAssertTrue(summary.isEditing)
        XCTAssertTrue(editor.draft.markdown.contains("\n"))
        let commandReturn = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
        XCTAssertTrue(editor.inputView.performKeyEquivalent(with: commandReturn))
        XCTAssertNotNil(saved)
        XCTAssertNil(summary.editor)
        summary.beginEditing()
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        summary.editor?.inputView.keyDown(with: escape)
        XCTAssertNil(summary.editor)
    }
}

/// Native summary fixtures shared with list integration tests; no coordinator or network is involved.
@MainActor
enum ReviewSummaryTestFixture {
    static func summary(body: String = "Original") -> AppKitReviewProposalSummaryView {
        let summary = AppKitReviewProposalSummaryView()
        summary.configure(configuration(body: body))
        return summary
    }

    static func configuration(
        body: String = "Original", proposalID: String? = "proposal", isEditable: Bool = true
    ) -> AppKitReviewProposalSummaryView.Configuration {
        .init(
            proposalID: proposalID, markdown: body,
            document: AppMarkdownParser().documentPreservingSource(for: body),
            isEditable: isEditable, typography: TranscriptTypography()
        )
    }

    static func descendant(in view: NSView, matching predicate: (NSView) -> Bool) -> NSView? {
        if predicate(view) { return view }
        for child in view.subviews {
            if let found = descendant(in: child, matching: predicate) { return found }
        }
        return nil
    }

    static func text(in view: NSView) -> String {
        let own = (view as? NSTextField)?.stringValue ?? (view as? NSTextView)?.string ?? ""
        return own + view.subviews.map { text(in: $0) }.joined(separator: "\n")
    }
}
