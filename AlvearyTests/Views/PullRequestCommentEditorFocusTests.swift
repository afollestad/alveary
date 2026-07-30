import AppKit
import BlockInputKit
import SwiftUI
import XCTest

@testable import Alveary

/// The inline edit/reply editor must keep its top content inset when the focus
/// token claims first responder on mount (the caret row previously rendered
/// flush against the editor chrome until the next height change).
@MainActor
final class PullRequestCommentEditorFocusTests: XCTestCase {
    func testFocusedEditorKeepsTopContentInset() async throws {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        viewModel.composerDraft = PullRequestCommentDraftBox(markdown: "Comment 1")
        var session = PullRequestPaneSession(
            generation: UUID(),
            summary: makePullRequestSummary(number: 7)
        )
        session.composerText = "Comment 1"
        session.composerFocusToken = UUID()

        let hosting = NSHostingView(rootView: PullRequestActivityCommentEditor(
            session: session,
            viewModel: viewModel
        ).padding(12))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 180)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let editor = try XCTUnwrap(firstBlockInputView(in: hosting))
        var textView: NSTextView?
        for _ in 0..<200 {
            window.displayIfNeeded()
            textView = firstTextView(in: editor)
            if let textView, window.firstResponder === textView {
                break
            }
            await Task.yield()
        }
        for _ in 0..<50 {
            await Task.yield()
        }
        window.displayIfNeeded()

        let focusedTextView = try XCTUnwrap(textView)
        XCTAssertTrue(window.firstResponder === focusedTextView)

        // The caret row must start below the editor's top content inset (8pt
        // section inset), not flush against the chrome.
        let textTopInEditor = editor.convert(focusedTextView.bounds.origin, from: focusedTextView).y
        XCTAssertGreaterThanOrEqual(textTopInEditor, 6)
    }

    private func firstBlockInputView(in view: NSView) -> BlockInputView? {
        if let match = view as? BlockInputView {
            return match
        }
        for subview in view.subviews {
            if let match = firstBlockInputView(in: subview) {
                return match
            }
        }
        return nil
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let match = view as? NSTextView {
            return match
        }
        for subview in view.subviews {
            if let match = firstTextView(in: subview) {
                return match
            }
        }
        return nil
    }
}
