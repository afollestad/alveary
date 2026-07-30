import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    private static let reviewAnchor = DiffCommentAnchor(path: "Sources/Parser.swift", side: .right, line: 12)

    private static func inertReviewInteraction(
        draftText: String = "",
        composerMode: DiffCommentComposerMode = .newComment,
        editingRemoteCommentID: Int? = nil,
        editingPendingAnchor: DiffCommentAnchor? = nil
    ) -> DiffCommentInteraction {
        DiffCommentInteraction(
            draft: PullRequestCommentDraftBox(markdown: draftText),
            composerMode: { _ in composerMode },
            composerErrorMessage: nil,
            composerFocusToken: nil,
            editingRemoteCommentID: editingRemoteCommentID,
            editingPendingAnchor: editingPendingAnchor,
            reactionOptions: PullRequestReactionContent.allCases.map {
                CommentReactionOption(content: $0.rawValue, emoji: $0.emoji)
            },
            // Nil avatar URLs render the deterministic letter placeholder.
            avatarLoader: GitHubAvatarLoader(),
            onComposerFocusConsumed: {},
            onAddComment: { _ in },
            onEditRemoteComment: { _, _ in },
            onDeleteRemoteComment: { _, _ in },
            onToggleReaction: { _, _ in },
            onReplyToThread: { _, _ in },
            onToggleThreadResolved: { _, _ in },
            onSaveDraft: {},
            onCancelComposer: {},
            onDeletePending: { _ in }
        )
    }

    func testDiffCommentThreadRow() {
        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "carol",
                    bodyMarkdown: "Consider clamping this before the fetch.",
                    isPending: false
                ),
                // An updatable/deletable submitted comment shows the three-dot menu
                // and its reaction chips (viewer reacted with the second one).
                DiffLineComment(
                    author: "afollestad",
                    bodyMarkdown: "Clamped in the latest push.",
                    isPending: false,
                    remoteID: 987,
                    nodeID: "PRRC_987",
                    canEdit: true,
                    canDelete: true,
                    reactions: [
                        CommentReaction(content: "THUMBS_UP", emoji: "👍", count: 2, viewerHasReacted: false),
                        CommentReaction(content: "HOORAY", emoji: "🎉", count: 1, viewerHasReacted: true)
                    ]
                ),
                DiffLineComment(
                    author: "You",
                    bodyMarkdown: "Will do — queuing a fix in this review.",
                    isPending: true
                )
            ]
        )

        assertMacSnapshot(
            DiffCommentThreadRow(
                thread: thread,
                anchor: Self.reviewAnchor,
                interaction: Self.inertReviewInteraction()
            )
            .padding(16),
            size: CGSize(width: 520, height: 300),
            named: "diff_comment_thread_row"
        )
    }

    func testDiffCommentThreadRowResolvedCollapsed() {
        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(author: "carol", bodyMarkdown: "Root", isPending: false, remoteID: 987),
                DiffLineComment(author: "afollestad", bodyMarkdown: "Done.", isPending: false, remoteID: 988)
            ],
            isResolved: true,
            threadID: "PRT_1"
        )

        assertMacSnapshot(
            DiffCommentThreadRow(
                thread: thread,
                anchor: Self.reviewAnchor,
                interaction: Self.inertReviewInteraction()
            )
            .padding(16),
            size: CGSize(width: 520, height: 120),
            named: "diff_comment_thread_row_resolved_collapsed"
        )
    }

    func testDiffCommentThreadRowInlineEditing() {
        // Editing a submitted comment swaps its body for the editor in place;
        // the author row stays and the standalone composer row never appears.
        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(author: "carol", bodyMarkdown: "Consider clamping this.", isPending: false, remoteID: 986),
                DiffLineComment(
                    author: "afollestad",
                    bodyMarkdown: "Clamped in the latest push.",
                    isPending: false,
                    remoteID: 987,
                    canEdit: true,
                    canDelete: true
                )
            ],
            threadID: "PRT_1"
        )

        assertMacSnapshot(
            DiffCommentThreadRow(
                thread: thread,
                anchor: Self.reviewAnchor,
                interaction: Self.inertReviewInteraction(
                    draftText: "Clamped in the latest push.",
                    composerMode: .editRemote,
                    editingRemoteCommentID: 987
                )
            )
            .padding(16),
            size: CGSize(width: 520, height: 300),
            named: "diff_comment_thread_row_inline_editing"
        )
    }

    func testDiffCommentComposerRow() {
        assertMacSnapshot(
            DiffCommentComposerRow(
                anchor: Self.reviewAnchor,
                interaction: Self.inertReviewInteraction(draftText: "This branch loses the trailing newline.")
            )
            .padding(16),
            size: CGSize(width: 520, height: 200),
            named: "diff_comment_composer_row"
        )
    }

    func testPullRequestPaneReviewFooterCollapsed() {
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 2)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 80),
            named: "pull_request_review_footer_collapsed"
        )
    }

    func testPullRequestPaneReviewFooterExpanded() {
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 1)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: true),
            size: CGSize(width: 460, height: 220),
            named: "pull_request_review_footer_expanded"
        )
    }

    func testPullRequestPaneReviewFooterExpandedOwnPullRequest() {
        // Your own PR: no Approve / Request changes picker, comment-only submit.
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 1, isAuthored: true)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: true),
            size: CGSize(width: 460, height: 220),
            named: "pull_request_review_footer_expanded_own_pr"
        )
    }
}

@MainActor
private struct PullRequestReviewFooterFixture {
    let viewModel: PullRequestsViewModel
    let session: PullRequestPaneSession

    init(pendingCommentCount: Int, isAuthored: Bool = false) {
        let service = StubPullRequestsService()
        viewModel = makePullRequestsViewModel(service: service)
        let summary = makePullRequestSummary(number: 7, isAuthored: isAuthored)
        viewModel.requestDetails(summary)
        for index in 0..<pendingCommentCount {
            let anchor = DiffCommentAnchor(path: "Sources/File\(index).swift", side: .right, line: index + 1)
            viewModel.openCommentComposer(at: anchor)
            viewModel.updateComposerText("Pending comment \(index + 1)")
            viewModel.saveComposerComment()
        }
        guard let session = viewModel.activePaneSession else {
            fatalError("Expected an active pane session for the footer fixture")
        }
        self.session = session
    }

    func footer(initiallyExpanded: Bool) -> some View {
        PullRequestPaneReviewFooter(
            viewModel: viewModel,
            session: session,
            initiallyExpanded: initiallyExpanded
        )
    }
}
