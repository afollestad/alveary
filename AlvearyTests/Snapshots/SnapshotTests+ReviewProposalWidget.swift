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
    /// badge where a server-draft comment wears "Pending", the summary line counts it, and it
    /// carries the two trailing controls — the accent "Show in pull request" and the pane's own
    /// three-dot actions menu, whose one row drops it from the review.
    func testReviewProposalWidgetProposedComment() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(commentIsProposed: true)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_proposed_comment"
        )
    }

    /// A card anchored to the diff's final line has the block's border under it instead of another
    /// line, and takes the wider outset so it does not crowd that border.
    func testReviewProposalWidgetTrailingCommentClearsTheBlockBorder() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(commentIsProposed: true, commentLine: 3)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_trailing_comment"
        )
    }

    /// Once a submission is in flight the review's comments are no longer the user's to change, so
    /// the Remove withdraws even from a staged comment.
    func testReviewProposalWidgetProposedCommentWhileSubmitting() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(isSubmitting: true, commentIsProposed: true)
            },
            size: CGSize(width: 700, height: 360),
            named: "review_proposal_widget_proposed_comment_submitting"
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

    /// A comment the diff can no longer place is listed under the preview rather than dropped, so
    /// the card's count and what it draws agree.
    func testReviewProposalWidgetStaleComment() {
        assertMacSnapshot(
            appKitRowSnapshot {
                ReviewProposalSnapshotFixture.widgetRow(
                    preview: .loaded(
                        ReviewProposalSnapshotFixture.loadedPreview(
                            commentIsProposed: true,
                            staleComments: [
                                PullRequestReviewProposalPreview.StaleComment(
                                    proposedIndex: 1,
                                    path: "Sources/Removed.swift",
                                    bodyMarkdown: "This branch is unreachable once the guard lands."
                                )
                            ]
                        )
                    )
                )
            },
            size: CGSize(width: 700, height: 460),
            named: "review_proposal_widget_stale_comment"
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

    /// "Show in PR" resting beside hovered, because hovering is the whole of this control's
    /// feedback — it draws no shape, so a baseline of the resting state alone would pass unchanged
    /// if the brightening were dropped. A whole card cannot show it: the fixture has no way to put
    /// the pointer on one control, so the pair is rendered directly, the way the transcript's
    /// approval controls are.
    func testReviewProposalCommentJumpButtonHoverState() {
        assertMacSnapshot(
            appKitRowSnapshot {
                // Contrast is pinned so the baseline cannot flip with the runner's own
                // Increase Contrast setting, which would erase the difference being captured.
                let resting = AppKitReviewProposalCommentJumpButton()
                resting.configure(fontSize: 11)
                resting.increasesContrast = { false }

                let hovered = AppKitReviewProposalCommentJumpButton()
                hovered.configure(fontSize: 11)
                hovered.increasesContrast = { false }
                hovered.mouseEntered(with: Self.reviewProposalHoverEvent)

                let stack = NSStackView(views: [resting, hovered])
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 24
                stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
                return stack
            },
            size: CGSize(width: 300, height: 52),
            named: "review_proposal_comment_jump_button_hover"
        )
    }

    /// `mouseEntered` reads nothing off the event, and `NSEvent.mouseEvent` rejects the tracking-area
    /// types outright, so a `.mouseMoved` stand-in drives it.
    private static var reviewProposalHoverEvent: NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) ?? NSEvent()
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
        commentIsProposed: Bool = false,
        commentLine: Int = 2
    ) -> AppKitTranscriptHostToolWidgetRowView {
        let entry = HostToolWidgetEntry(
            id: "tool-review-proposal",
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            content: .pullRequestReviewProposal(widgetContent(commentIsProposed: commentIsProposed)),
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
                        stagedComments: commentIsProposed
                            ? [stagedComment(body: commentBody, line: commentLine)]
                            : []
                    ),
                    preview: preview ?? .loaded(
                        loadedPreview(
                            viewerIsAuthor: viewerIsAuthor,
                            commentBody: commentBody,
                            commentIsBot: commentIsBot,
                            commentIsProposed: commentIsProposed,
                            commentLine: commentLine
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

    /// The call snapshot a proposal card renders its header from.
    static func widgetContent(commentIsProposed: Bool) -> PullRequestReviewProposalWidgetContent {
        PullRequestReviewProposalWidgetContent(
            event: .approve,
            identifier: identifier,
            body: "Only the retry loop still worries me.",
            commentCount: commentIsProposed ? 1 : nil,
            pendingCommentCount: commentIsProposed ? 0 : 2,
            proposalID: proposalID,
            message: "Opened a review confirmation in Alveary.",
            status: .pendingConfirmation
        )
    }

    /// Takes the same line the preview anchors, so the envelope and the rendered card agree.
    static func stagedComment(body: String, line: Int = 2) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(
            path: "Sources/Retry.swift",
            line: line,
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
    /// `commentLine` 3 anchors the diff's final line, which is what leaves the card last in the
    /// block with only its border below it.
    static func loadedPreview(
        viewerIsAuthor: Bool = false,
        commentBody: String = "This retries forever when the server keeps answering 503.",
        commentIsBot: Bool = false,
        commentIsProposed: Bool = false,
        commentLine: Int = 2,
        staleComments: [PullRequestReviewProposalPreview.StaleComment] = []
    ) -> PullRequestReviewProposalPreview {
        var annotations = DiffCommentAnnotations()
        annotations.allowsComposing = false
        annotations.threads[
            DiffCommentAnchor(path: "Sources/Retry.swift", side: .right, line: commentLine)
        ] = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "viewer",
                    bodyMarkdown: commentBody,
                    isPending: !commentIsProposed,
                    nodeID: commentIsProposed ? nil : "PENDING_COMMENT_1",
                    isBot: commentIsBot,
                    proposedIndex: commentIsProposed ? 0 : nil
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
            staleComments: staleComments,
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
