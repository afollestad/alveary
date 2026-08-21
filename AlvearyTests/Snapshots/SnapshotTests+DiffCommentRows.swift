import SwiftUI
import XCTest

@testable import Alveary

/// Baselines for the diff comment rows the pull request Changes tab renders through
/// `FlattenedDiffPreview`. The review footer's own baselines are `SnapshotTests+PullRequestReview`.
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

    /// A bot's `<details>` section, collapsed, as the comment's **last** block — where the gap a
    /// disagreeing view and measurer would leave lands against the card's bottom edge, visible
    /// rather than buried between paragraphs. The second comment repeats the first's summary text
    /// on purpose: their disclosure state is namespaced per comment, so only one opens at a time.
    func testDiffCommentThreadRowCollapsedDetails() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "ci-bot",
                    bodyMarkdown: "Coverage dropped by 0.4%.\n\n<details><summary>Test run logs</summary>\n\nfailing case: row 42\n\n</details>",
                    isPending: false,
                    remoteID: 987,
                    nodeID: "PRRC_987",
                    isBot: true
                ),
                DiffLineComment(
                    author: "carol",
                    bodyMarkdown: "<details><summary>Test run logs</summary>\n\na different body\n\n</details>",
                    isPending: false,
                    remoteID: 988,
                    nodeID: "PRRC_988"
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
            size: CGSize(width: 520, height: 240),
            named: "diff_comment_thread_row_collapsed_details"
        )
    }

    /// The other half of the disclosure: `open` renders it expanded from the first frame, with the
    /// body indented under its summary. Together with the collapsed baseline this pins both states
    /// a reader can land on without interacting.
    func testDiffCommentThreadRowExpandedDetails() {
        AppMarkdownDetailsExpansionStore.removeAll()
        let thread = DiffLineCommentThread(
            comments: [
                DiffLineComment(
                    author: "ci-bot",
                    bodyMarkdown: "Coverage dropped by 0.4%.\n\n<details open><summary>Test run logs</summary>\n\nfailing case: row 42\n\n</details>",
                    isPending: false,
                    remoteID: 987,
                    nodeID: "PRRC_987",
                    isBot: true
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
            size: CGSize(width: 520, height: 220),
            named: "diff_comment_thread_row_expanded_details"
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
}
