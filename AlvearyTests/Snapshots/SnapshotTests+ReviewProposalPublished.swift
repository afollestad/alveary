import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testReviewProposalWidgetSubmittedWithComments() {
        assertMacSnapshot(
            appKitRowSnapshot { ReviewProposalSnapshotFixture.publishedRow() },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_submitted_with_comments"
        )
    }

    func testReviewProposalWidgetSubmittedEditingComment() {
        assertMacSnapshot(
            appKitRowSnapshot {
                let row = ReviewProposalSnapshotFixture.publishedRow()
                let menu = ReviewSummaryTestFixture.descendant(in: row) { $0 is AppKitReviewProposalCommentMenuButton }
                    as? AppKitReviewProposalCommentMenuButton
                let edit = menu?.makeMenu().items.first { $0.title == PullRequestCommentActionsMenu.editTitle }
                XCTAssertNotNil(edit, "The baseline needs the editor open.")
                _ = edit.flatMap { $0.target?.perform($0.action, with: $0) }
                return row
            },
            size: CGSize(width: 700, height: 420),
            named: "review_proposal_widget_submitted_editing_comment"
        )
    }
}

extension ReviewProposalSnapshotFixture {
    /// A submitted card whose published comment the viewer may still edit and delete.
    static func publishedRow() -> AppKitTranscriptHostToolWidgetRowView {
        let review = PullRequestPublishedReview(
            identifier: identifier, sourceConversationID: "source-conversation", files: loadedPreview().files,
            viewerLogin: "viewer", viewerAvatarURL: nil, reviewers: [],
            comments: [.fixture(path: "Sources/Retry.swift", line: 2, body: "This retries forever when the server keeps answering 503.")]
        )
        let entry = HostToolWidgetEntry(
            id: "tool-review-proposal",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            content: .pullRequestReviewProposal(widgetContent(commentIsProposed: true)),
            isComplete: true,
            outcomeKey: proposalID,
            outcome: .confirmed,
            outcomeTitle: "comment",
            outcomeBody: "Only the retry loop still worries me.",
            publishedReview: review
        )
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(.init(
            entry: entry,
            reviewProposal: ReviewProposalWidgetState(published: .init(review: review, allowsActions: true)),
            isProposalInteractive: false,
            bubbleMaxWidth: 640
        ))
        return view
    }
}
