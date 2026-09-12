import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testReviewProposalStaleCommentVotes() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let view = AppKitReviewProposalStaleCommentsView()
                view.configure(.init(
                    comments: (0..<2).map { index in
                        PullRequestReviewProposalPreview.StaleComment(
                            proposedIndex: index, path: "Sources/Retry\(index).swift",
                            bodyMarkdown: "**[P2]** Could this retry stop when `Task.isCancelled` is true?",
                            evidence: ReviewProposalSnapshotFixture.collectiveEvidence
                        )
                    },
                    allowsRemoval: true, typography: TranscriptTypography()
                ))
                return view
            },
            size: CGSize(width: 700, height: 210),
            named: "review_proposal_stale_comment_votes",
            colorScheme: .dark
        )
    }

    func testReviewProposalWidgetCollectiveVotes() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.expandedCollectiveWidgetRow() },
            size: CGSize(width: 700, height: 680),
            named: "review_proposal_collective_votes"
        )
    }

    func testReviewProposalWidgetPartialTeamApproval() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.partialApprovalWidgetRow() },
            size: CGSize(width: 700, height: 240),
            named: "review_proposal_partial_team_approval"
        )
    }

    func testReviewProposalVoteDetailsWithMixedDecisions() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.mixedVoteEvidenceView() },
            size: CGSize(width: 700, height: 460),
            named: "review_proposal_mixed_vote_details"
        )
    }

    func testReviewProposalVoteDetailsWithMixedDecisionsDark() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.mixedVoteEvidenceView() },
            size: CGSize(width: 700, height: 460),
            named: "review_proposal_mixed_vote_details_dark",
            colorScheme: .dark
        )
    }

    func testPullRequestPaneChangesCollectiveVotes() throws {
        let comment = collectivePaneComment(path: "File0.swift")
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal(
            comments: [comment, collectivePaneComment(path: "Removed.swift")]
        )
        assertMacSnapshot(
            PullRequestPaneFiles(
                session: PullRequestPaneSnapshots.loadedSession, viewModel: viewModel, target: PullRequestPaneSnapshots.target
            ),
            size: CGSize(width: 460, height: 620),
            named: "pull_request_changes_collective_votes"
        )
    }

    func testPullRequestPaneOverviewCollectiveVotes() throws {
        let viewModel = try PullRequestPaneSnapshots.viewModelWithPendingProposal(comments: [collectivePaneComment(path: "File0.swift")])
        let session = PullRequestPaneSnapshots.loadedSession
        var detail = try XCTUnwrap(session.detail)
        detail.comments = []
        detail.reviews = []
        detail.reviewThreads = []
        detail.timelineEvents = []
        assertMacSnapshot(
            PullRequestPaneActivitySection(session: session, detail: detail, viewModel: viewModel, onOpenFiles: {})
                .padding(16),
            size: CGSize(width: 460, height: 250),
            named: "pull_request_overview_collective_votes"
        )
    }

    private func collectivePaneComment(path: String) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(
            id: "collective:\(path)", path: path, line: 2, side: "RIGHT",
            body: "**[P2]** Prefer `guard let` over the force unwrap here.",
            evidence: ReviewProposalSnapshotFixture.collectiveEvidence
        )
    }
}
