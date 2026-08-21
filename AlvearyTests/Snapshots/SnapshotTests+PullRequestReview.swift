import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
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

    func testPullRequestPaneReviewFooterAgenticReviewWorking() {
        // A running review swaps the brain glyph for the shared spinner in the same box — so the
        // pill cannot change width — and dims, because the route is unavailable until that
        // thread's first turn ends rather than merely busy for a moment.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .open,
            selectedReviewAction: .agenticReview,
            workingAgenticKinds: [.review]
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_agentic_working"
        )
    }

    func testPullRequestPaneReviewFooterAddressFeedbackIdleWhileReviewWorks() {
        // The two routes are independent: a running review leaves Address feedback fully live on
        // the face, which is what the caret exists to reach.
        let fixture = PullRequestReviewFooterFixture(
            pendingCommentCount: 0,
            status: .open,
            selectedReviewAction: .addressFeedback,
            workingAgenticKinds: [.review]
        )

        assertMacSnapshot(
            fixture.footer(initiallyExpanded: false),
            size: CGSize(width: 460, height: 100),
            named: "pull_request_review_footer_other_route_idle"
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
        workingAgenticKinds: Set<PullRequestAgenticThreadService.Kind> = []
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
        if !workingAgenticKinds.isEmpty {
            viewModel.mutateActiveSession { session in
                session.workingAgenticKinds = workingAgenticKinds
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
