import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    private static let reviewAnchor = DiffCommentAnchor(path: "Sources/Parser.swift", side: .right, line: 12)

    private static func inertReviewInteraction(
        draftText: String = "",
        composerMode: DiffCommentComposerMode = .newComment,
        editingRemoteCommentID: Int? = nil,
        editingPendingCommentNodeID: String? = nil
    ) -> DiffCommentInteraction {
        DiffCommentInteraction(
            draft: PullRequestCommentDraftBox(markdown: draftText),
            composerMode: { _ in composerMode },
            composerErrorMessage: nil,
            composerFocusToken: nil,
            editingRemoteCommentID: editingRemoteCommentID,
            editingPendingCommentNodeID: editingPendingCommentNodeID,
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
                // The timestamp renders trailing, just left of the menu slot,
                // matching the Overview timeline's comment cards.
                DiffLineComment(
                    author: "carol",
                    bodyMarkdown: "Consider clamping this before the fetch.",
                    isPending: false,
                    relativeAge: "1d",
                    absoluteTimestamp: "Jul 28, 2026 at 8:30 PM"
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
                // The viewer's own unsubmitted comment: orange Pending pill, the
                // three-dot menu (addressed by node id, not the REST id), and no
                // reaction bar — GitHub takes none until the review is submitted.
                DiffLineComment(
                    author: "You",
                    bodyMarkdown: "Will do — queuing a fix in this review.",
                    isPending: true,
                    nodeID: "PRRC_pending",
                    canEdit: true,
                    canDelete: true
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
        // With write permission the collapsed row splits evenly between the state
        // button and Submit review...; the pending count moves above them. An open
        // pull request carries two state actions, so the state half is the split
        // button — Close PR on the primary side, Mark as draft behind the caret.
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 2, status: .open)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_collapsed"
        )
    }

    func testPullRequestPaneReviewFooterCollapsedAgenticReviewSelected() {
        // The persisted caret pick puts Agentic review — brain glyph — on the split
        // button's primary side; Submit review... waits behind the caret.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .open,
            selectedReviewAction: .agenticReview
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_collapsed_agentic_selected"
        )
    }

    func testPullRequestPaneReviewFooterDefaultsToAddressFeedbackOnYourOwnPullRequest() {
        // Nothing stored: your own pull request opens on answering the feedback it received,
        // wearing the same brain glyph as Agentic review.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            isAuthored: true,
            status: .open,
            selectedReviewAction: nil
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_authored_default"
        )
    }

    func testPullRequestPaneReviewFooterDefaultsToAgenticReviewOnSomebodyElses() {
        // The same footer on a pull request you did not write leads with reviewing instead.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .open,
            selectedReviewAction: nil
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_others_default"
        )
    }

    func testPullRequestPaneReviewFooterAgenticReviewStarting() {
        // Starting the review swaps the brain glyph for the shared spinner in the same box, so
        // the pill neither greys out nor changes width while the thread is being created.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .open,
            selectedReviewAction: .agenticReview,
            isStartingAgenticThread: true
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_agentic_starting"
        )
    }

    func testPullRequestPaneReviewFooterClosedWithDeletedBranch() {
        // A closed pull request whose branch is gone: Reopen PR is dead and the
        // note above says why.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .closed,
            headRefExists: false
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_closed_deleted_branch"
        )
    }

    func testPullRequestPaneReviewFooterDraft() {
        // A draft carries two state actions, so the button splits: the primary
        // side defaults to Ready for review, the caret opens the other.
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 0, status: .draft)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_draft"
        )
    }

    func testPullRequestPaneReviewFooterWithoutWritePermission() {
        // No permission to close: the footer keeps the single trailing action.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 2,
            status: .open,
            viewerCanUpdate: false
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_no_write_access"
        )
    }

    func testPullRequestPaneReviewFooterLoading() {
        // No detail yet: the even split still paints, with a disabled stand-in
        // titled from the list row's status instead of a lone trailing button.
        let fixture = PullRequestReviewFooterFixture(pendingCommentCount: 0, summaryStatus: .closed)

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_loading"
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

    /// Both resolution states, because each carries a different glyph and the
    /// pane's own fixtures only ever render the footer unresolved.
    func testPullRequestThreadActionsFooterBothResolutionStates() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 12) {
                PullRequestThreadActionsFooter(
                    isResolved: false,
                    canReply: true,
                    canResolve: true,
                    onReply: {},
                    onToggleResolved: {}
                )
                PullRequestThreadActionsFooter(
                    isResolved: true,
                    canReply: true,
                    canResolve: true,
                    onReply: {},
                    onToggleResolved: {}
                )
            }
            .padding(16),
            size: CGSize(width: 400, height: 110),
            named: "pull_request_thread_actions_footer_states"
        )
    }
}

/// Internal (not file-private) so the pane-footer chrome parity snapshot can
/// render the real review footer beside a `ContextualPaneFooter`.
@MainActor
struct PullRequestReviewFooterFixture {
    let viewModel: PullRequestsViewModel
    let session: PullRequestPaneSession

    /// A nil `status` leaves the session without a detail — the still-loading
    /// case, which renders the disabled stand-in from `summaryStatus`.
    init(
        pendingCommentCount: Int,
        isAuthored: Bool = false,
        status: PullRequestStatus? = nil,
        summaryStatus: PullRequestStatus = .open,
        viewerCanUpdate: Bool = true,
        headRefExists: Bool = true,
        selectedReviewAction: PullRequestReviewFooterAction.Kind? = .submitReview,
        isStartingAgenticThread: Bool = false
    ) {
        let service = StubPullRequestsService()
        // The footer seeds its split-button selection from settings at init, so the stored
        // kind is what puts a particular option on the button's primary side. Both authorship
        // keys are written because the fixture renders either side; nil stores neither, which
        // is what leaves the packaged authorship defaults showing.
        let settingsService = InMemorySettingsService()
        if let selectedReviewAction {
            settingsService.update {
                $0.pullRequestOwnFooterActionKind = selectedReviewAction.rawValue
                $0.pullRequestOthersFooterActionKind = selectedReviewAction.rawValue
            }
        }
        viewModel = makePullRequestsViewModel(service: service, settingsService: settingsService)
        let summary = makePullRequestSummary(number: 7, status: summaryStatus, isAuthored: isAuthored)
        viewModel.requestDetails(summary)
        // The stubbed detail fetch never resolves, so seed the session directly.
        // Pending comments live on the detail now, so the count comes from seeded
        // threads rather than driving the composer, which would need a network
        // round trip to settle. A nil `status` with no pending comments is the
        // still-loading case, which deliberately leaves `detail` nil.
        if status != nil || pendingCommentCount > 0 {
            viewModel.mutateActiveSession { session in
                session.detail = makePullRequestDetail(
                    id: summary.id,
                    status: status ?? .open,
                    reviewThreads: (0..<pendingCommentCount).map(Self.pendingThread(index:)),
                    viewerCanUpdate: viewerCanUpdate,
                    headRefExists: headRefExists,
                    pendingReviewNodeID: pendingCommentCount > 0 ? "PRR_pending" : nil
                )
            }
        }
        if isStartingAgenticThread {
            viewModel.mutateActiveSession { session in
                session.isStartingAgenticThread = true
            }
        }
        guard let session = viewModel.activePaneSession else {
            fatalError("Expected an active pane session for the footer fixture")
        }
        self.session = session
    }

    private static func pendingThread(index: Int) -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: "Sources/File\(index).swift",
            line: index + 1,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: "afollestad",
                    authorAvatarURL: nil,
                    bodyMarkdown: "Pending comment \(index + 1)",
                    createdAt: nil,
                    nodeID: "PRRC_pending_\(index)",
                    viewerCanUpdate: true,
                    viewerCanDelete: true,
                    isPending: true
                )
            ],
            nodeID: "PRT_pending_\(index)"
        )
    }

    func footer(initiallyExpanded: Bool) -> some View {
        PullRequestPaneReviewFooter(
            viewModel: viewModel,
            session: session,
            target: .details(PullRequestPaneSnapshots.identifier),
            initiallyExpanded: initiallyExpanded
        )
    }
}
