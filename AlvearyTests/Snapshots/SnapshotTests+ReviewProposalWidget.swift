import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testReviewProposalWidgetPendingWithComments() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow()
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_pending"
        )
    }

    func testReviewProposalWidgetPendingWithCommentsDark() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow()
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_pending_dark",
            colorScheme: .dark
        )
    }

    /// GitHub refuses approve and request-changes on your own pull request, so the split button's
    /// primary half is disabled on the proposed verdict rather than failing at submission.
    func testReviewProposalWidgetSelfReviewVerdictDisabled() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(viewerIsAuthor: true)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_self_review"
        )
    }

    /// A staged comment exists only in Alveary until confirmed: its card wears the "Proposed"
    /// badge where a server-draft comment wears "Pending", and the summary line counts it.
    func testReviewProposalWidgetProposedComment() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(commentIsProposed: true)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_proposed_comment"
        )
    }

    /// The comment card's chrome, mirroring the Changes tab: the `Bot` pill beside the author and
    /// a markdown-rendered body rather than the plain text the card used to show.
    func testReviewProposalWidgetBotCommentWithMarkdown() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(
                    commentBody: "Use `withTaskCancellationHandler` here, per [the docs](https://example.com).",
                    commentIsBot: true
                )
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_bot_comment"
        )
    }

    /// The card stays usable while its diff loads; the decision does not depend on it.
    func testReviewProposalWidgetLoadingPreview() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(preview: .loading)
            },
            size: CGSize(width: 700, height: 200),
            named: "review_proposal_widget_loading"
        )
    }

    func testReviewProposalWidgetSubmitting() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(isSubmitting: true)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_submitting"
        )
    }

    func testReviewProposalWidgetSubmissionFailed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(
                    errorMessage: "GitHub rejected the review: you have reached a rate limit."
                )
            },
            size: CGSize(width: 700, height: 380),
            named: "review_proposal_widget_failed"
        )
    }

    func testReviewProposalWidgetConfirmed() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(outcome: .confirmed, submittedEvent: "request_changes")
            },
            size: CGSize(width: 700, height: 140),
            named: "review_proposal_widget_confirmed"
        )
    }

    func testReviewProposalWidgetRejected() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(outcome: .rejected)
            },
            size: CGSize(width: 700, height: 140),
            named: "review_proposal_widget_rejected"
        )
    }
}

/// Builds review-proposal cards without the coordinator, so a baseline never depends on GitHub.
@MainActor
enum ReviewProposalSnapshotFixture {
    static let proposalID = "review-proposal-snapshot"
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    static func widgetRow(
        preview: PullRequestReviewProposalPreviewState? = nil,
        isSubmitting: Bool = false,
        errorMessage: String? = nil,
        outcome: HostToolWidgetOutcome? = nil,
        submittedEvent: String? = nil,
        viewerIsAuthor: Bool = false,
        commentBody: String = "This retries forever when the server keeps answering 503.",
        commentIsBot: Bool = false,
        commentIsProposed: Bool = false
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let content = PullRequestReviewProposalWidgetContent(
            event: .approve,
            identifier: identifier,
            body: "Only the retry loop still worries me.",
            commentCount: commentIsProposed ? 1 : nil,
            pendingCommentCount: commentIsProposed ? 0 : 2,
            proposalID: proposalID,
            message: "Opened a review confirmation in Alveary.",
            status: .pendingConfirmation
        )
        let entry = HostToolWidgetEntry(
            id: "tool-review-proposal",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            content: .pullRequestReviewProposal(content),
            isComplete: true,
            outcomeKey: proposalID,
            outcome: outcome,
            outcomeTitle: submittedEvent
        )
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(
            .init(
                entry: entry,
                reviewProposal: ReviewProposalWidgetState(
                    presentation: presentation(
                        stagedComments: commentIsProposed ? [stagedComment(body: commentBody)] : []
                    ),
                    preview: preview ?? .loaded(
                        loadedPreview(
                            viewerIsAuthor: viewerIsAuthor,
                            commentBody: commentBody,
                            commentIsBot: commentIsBot,
                            commentIsProposed: commentIsProposed
                        )
                    ),
                    selectedEvent: .approve,
                    canSubmit: true,
                    isSubmitting: isSubmitting,
                    errorMessage: errorMessage
                ),
                isProposalInteractive: outcome == nil,
                bubbleMaxWidth: 640
            )
        )
        return view
    }

    static func stagedComment(body: String) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(
            path: "Sources/Retry.swift",
            line: 2,
            side: "RIGHT",
            body: body
        )
    }

    static func presentation(
        stagedComments: [PullRequestReviewProposalRecord.Comment] = []
    ) -> PullRequestReviewProposalPresentation {
        PullRequestReviewProposalPresentation(
            id: proposalID,
            sourceConversationID: "source-conversation",
            identifier: identifier,
            title: "Retry transient GitHub failures",
            proposedEvent: .approve,
            body: "Only the retry loop still worries me.",
            comments: stagedComments,
            pendingCommentCount: stagedComments.isEmpty ? 2 : 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// One commented hunk, which is what the card is for: the review's comments on their lines.
    static func loadedPreview(
        viewerIsAuthor: Bool = false,
        commentBody: String = "This retries forever when the server keeps answering 503.",
        commentIsBot: Bool = false,
        commentIsProposed: Bool = false
    ) -> PullRequestReviewProposalPreview {
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = false
        annotations.threads[
            DiffCommentAnchor(path: "Sources/Retry.swift", side: .right, line: 2)
        ] = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "viewer",
                    bodyMarkdown: commentBody,
                    isPending: !commentIsProposed,
                    nodeID: commentIsProposed ? nil : "PENDING_COMMENT_1",
                    isBot: commentIsBot,
                    isProposed: commentIsProposed
                )
            ],
            isPending: !commentIsProposed
        )
        return PullRequestReviewProposalPreview(
            files: DiffParser.parse(
                """
                diff --git a/Sources/Retry.swift b/Sources/Retry.swift
                --- a/Sources/Retry.swift
                +++ b/Sources/Retry.swift
                @@ -1,2 +1,3 @@
                 func retry() {
                +    while true { attempt() }
                 }
                """
            ),
            annotations: annotations,
            pendingCommentCount: commentIsProposed ? 0 : 2,
            proposedCommentCount: commentIsProposed ? 1 : 0,
            hiddenFileCount: 0,
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
