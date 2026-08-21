import SwiftUI

/// The staged comments the current diff cannot place, listed above the Changes tab's diff.
///
/// A comment row is only ever emitted from a rendered line, so a staged comment whose anchor
/// resolves nowhere would otherwise vanish from this tab — taking its three-dot menu, the one
/// delete affordance the pane gives a staged comment, with it. This mirrors the transcript card's
/// list: the pane's own outdated treatment (the orange pill, a path with no line, no jump), the
/// pane's own comment menu, and the same one action.
///
/// Listed above the diff rather than under it the way the card does: the card's diff is at most
/// five files, while this tab's can run to hundreds — a notice at the bottom of that scroll would
/// read as the comment simply being gone.
struct PullRequestPaneStaleComments: View {
    let comments: [PullRequestReviewProposalPreview.StaleComment]
    /// False while the proposal submits, hiding each row's menu — its only action is a removal
    /// the coordinator refuses mid-submit. Mirrors the transcript list's `allowsRemoval`.
    let allowsRemoval: Bool
    /// Drops one staged comment by its position in the stored envelope.
    let onRemove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.caption(for: comments.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(comments, id: \.proposedIndex) { comment in
                row(for: comment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextualPaneHorizontalInsets()
        .padding(.top, 8)
    }

    /// Word-for-word the transcript card's caption (`AppKitReviewProposalStaleCommentsView`): the
    /// two surfaces report the same fact about the same envelope, and different sentences would
    /// read as different conditions.
    static func caption(for count: Int) -> String {
        count == 1
            ? "1 comment no longer matches the diff and will not be published."
            : "\(count) comments no longer match the diff and will not be published."
    }

    private func row(for comment: PullRequestReviewProposalPreview.StaleComment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(comment.path)
                    .font(.caption.weight(.medium))
                    .truncationMode(.middle)
                    .lineLimit(1)
                PullRequestCommentBadge("Outdated", color: .orange)
                Spacer(minLength: 0)
                if allowsRemoval {
                    PullRequestCommentActionsMenu(
                        onEdit: nil,
                        onDelete: { onRemove(comment.proposedIndex) }
                    )
                }
            }
            // A stale comment exists only inside the proposal envelope, so its array position
            // is the only identity available to separate its disclosure state from a sibling's.
            AppMarkdownText(
                markdown: comment.bodyMarkdown,
                taskStateScope: "stale:\(comment.path):\(comment.proposedIndex)"
            )
        }
        .accessibilityElement(children: .contain)
        // No line to name — that is the whole point — so the label says the file and the reason.
        .accessibilityLabel("Outdated comment on \(comment.path)")
    }
}
