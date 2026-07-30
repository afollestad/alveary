import SwiftUI

/// A review thread rendered in the Overview timeline: location header, diff-hunk
/// excerpt, then the thread's comments with the same edit/delete affordances the
/// Changes tab offers on them.
struct PullRequestReviewThreadView: View {
    /// The card's own rounding. The connecting rail turns on this same radius, so
    /// changing it here moves both.
    static let cardCornerRadius: CGFloat = 12

    let thread: PullRequestReviewThread
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel
    let onOpenFiles: () -> Void

    /// Resolved threads collapse their whole conversation — replies included — to
    /// the shared resolved header; this remembers an explicit expand. Resolution
    /// changes reset it, so resolving collapses and unresolving expands.
    @State private var isManuallyExpanded = false

    private var showsContent: Bool {
        !thread.isResolved || isManuallyExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(location)
                    .font(.caption.weight(.medium).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                if thread.isPending {
                    PullRequestCommentBadge("Pending", color: .orange)
                }

                if thread.isOutdated {
                    // Orange, matching GitHub's outdated treatment.
                    PullRequestCommentBadge("Outdated", color: .orange)
                }

                Spacer(minLength: 0)

                if !thread.isOutdated {
                    Button("Show in Changes") {
                        onOpenFiles()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("Switches to the Changes tab")
                }
            }

            if thread.isResolved {
                PullRequestResolvedThreadHeader(
                    commentCount: thread.comments.count,
                    isExpanded: $isManuallyExpanded
                )
            }

            if showsContent {
                if let excerpt = thread.diffHunkExcerpt {
                    Text(excerpt)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .accessibilityLabel("Code context")
                }

                ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
                    commentView(comment)
                }

                if isReplyingInline {
                    PullRequestActivityCommentEditor(
                        session: session,
                        viewModel: viewModel,
                        saveTitle: "Reply",
                        placeholder: "Leave a comment"
                    )
                } else if !thread.isPending, thread.replyTargetCommentID != nil || thread.nodeID != nil {
                    PullRequestThreadActionsFooter(
                        isResolved: thread.isResolved,
                        canReply: thread.replyTargetCommentID != nil,
                        canResolve: thread.nodeID != nil,
                        onReply: { viewModel.openThreadReplyComposer(thread) },
                        onToggleResolved: {
                            viewModel.setThreadResolved(threadID: thread.nodeID, resolved: !thread.isResolved)
                        }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .onChange(of: thread.isResolved) { _, _ in
            isManuallyExpanded = false
        }
    }

    private func commentView(_ comment: PullRequestComment) -> some View {
        let isEditing = isEditingInline(comment)
        return VStack(alignment: .leading, spacing: 8) {
            // Same author treatment as the comment cards above; a thread
            // comment is still a comment, so its header must not read lighter.
            PullRequestCommentAuthorRow(
                login: comment.authorLogin,
                avatarURL: comment.authorAvatarURL,
                isBot: comment.isBot,
                avatarLoader: viewModel.avatarLoader,
                authorFont: .subheadline.weight(.medium),
                authorIsProminent: true
            ) {
                Spacer(minLength: 0)

                if let date = comment.createdAt {
                    PullRequestTimestampLabel(date: date, referenceDate: viewModel.referenceDate)
                }

                if isActionable(comment), !isEditing {
                    PullRequestCommentActionsMenu(
                        onEdit: comment.viewerCanUpdate ? { viewModel.openThreadCommentEditor(comment) } : nil,
                        onDelete: comment.viewerCanDelete ? { viewModel.requestDeleteThreadComment(comment) } : nil
                    )
                }
            }

            if isEditing {
                PullRequestActivityCommentEditor(session: session, viewModel: viewModel)
            } else {
                PullRequestCommentBody(
                    markdown: comment.bodyMarkdown,
                    // A pending comment is not published, so GitHub takes no
                    // reactions on it; withholding the node id hides the bar.
                    nodeID: comment.isPending ? nil : comment.nodeID,
                    reactions: comment.reactions,
                    viewModel: viewModel
                )
            }
        }
    }

    /// Permission-gated like the Changes tab: the menu needs at least one of
    /// GitHub's viewer permissions (never authorship) plus the id its actions are
    /// addressed by — a node id when pending, a REST id when submitted.
    private func isActionable(_ comment: PullRequestComment) -> Bool {
        let hasActionableID = comment.isPending ? comment.nodeID != nil : comment.databaseId != nil
        return hasActionableID && (comment.viewerCanUpdate || comment.viewerCanDelete)
    }

    /// The same inline-edit state the Changes tab renders in its thread rows, so
    /// an edit opened on either tab shows in both.
    private func isEditingInline(_ comment: PullRequestComment) -> Bool {
        if comment.isPending {
            guard let nodeID = comment.nodeID else {
                return false
            }
            return session.composerPendingCommentNodeID == nodeID
        }
        guard let databaseId = comment.databaseId else {
            return false
        }
        return session.composerRemoteCommentID == databaseId
    }

    /// The reply editor renders inline in this thread only for a reply opened
    /// here: an open reply composer targeting this thread's root comment with no
    /// diff anchor. Changes-tab replies carry an anchor and render there instead.
    private var isReplyingInline: Bool {
        guard let replyTarget = thread.replyTargetCommentID else {
            return false
        }
        return session.composerAnchor == nil && session.composerReplyToCommentID == replyTarget
    }

    private var location: String {
        if let line = thread.line {
            return "\(thread.path):\(line)"
        }
        return thread.path
    }
}
