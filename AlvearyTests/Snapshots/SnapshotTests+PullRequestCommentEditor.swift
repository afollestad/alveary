import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    // The inline edit editor as it first appears over an existing comment:
    // two-line default height with the text starting at the editor's top inset.
    func testPullRequestActivityCommentEditorInitial() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        viewModel.composerDraft = PullRequestCommentDraftBox(markdown: "Comment 1")
        var session = PullRequestPaneSession(
            generation: UUID(),
            summary: makePullRequestSummary(number: 7)
        )
        session.composerText = "Comment 1"

        assertMacSnapshot(
            PullRequestActivityCommentEditor(session: session, viewModel: viewModel)
                .padding(12),
            size: CGSize(width: 460, height: 180),
            named: "pull_request_comment_editor_initial"
        )
    }

    // Same editor, but with the focus token set — the mounted editor claims first
    // responder like a real Edit click, which must not disturb the top inset.
    func testPullRequestActivityCommentEditorFocused() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        viewModel.composerDraft = PullRequestCommentDraftBox(markdown: "Comment 1")
        var session = PullRequestPaneSession(
            generation: UUID(),
            summary: makePullRequestSummary(number: 7)
        )
        session.composerText = "Comment 1"
        session.composerFocusToken = UUID()

        assertMacSnapshot(
            PullRequestActivityCommentEditor(session: session, viewModel: viewModel)
                .padding(12),
            size: CGSize(width: 460, height: 180),
            named: "pull_request_comment_editor_focused"
        )
    }
}
