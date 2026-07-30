import SwiftUI

/// Chronological conversation appended below the Overview content: issue comments
/// and reviews merged by date, followed by inline review threads.
struct PullRequestPaneActivitySection: View {
    let session: PullRequestPaneSession
    let detail: PullRequestDetail
    let viewModel: PullRequestsViewModel
    /// Switches the pane to the Changes tab, where the thread renders inline in the diff.
    let onOpenFiles: () -> Void

    /// The Overview appends this section — behind a divider — only when there
    /// is something to show.
    static func hasContent(detail: PullRequestDetail) -> Bool {
        !PullRequestActivityEntry.entries(from: detail).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Comment-action failures without an open inline editor land here —
            // the surface the action came from. The Changes tab shows the same
            // session error, and open editors render it inline instead.
            if let error = session.composerError, !hasOpenComposer {
                InlineBanner(
                    message: error,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: { viewModel.clearCommentActionError() }
                )
            }

            ForEach(PullRequestActivityEntry.entries(from: detail)) { entry in
                if case .thread(let thread) = entry.kind {
                    PullRequestReviewThreadView(
                        thread: thread,
                        session: session,
                        viewModel: viewModel,
                        onOpenFiles: onOpenFiles
                    )
                } else if !entry.nestedThreads.isEmpty {
                    PullRequestActivityReviewGroupView(
                        entry: entry,
                        session: session,
                        viewModel: viewModel,
                        onOpenFiles: onOpenFiles
                    )
                } else {
                    PullRequestActivityEntryView(entry: entry, session: session, viewModel: viewModel)
                }
            }
        }
    }

    private var hasOpenComposer: Bool {
        session.composerAnchor != nil
            || session.composerRemoteCommentID != nil
            || session.composerIssueCommentID != nil
            || session.composerReviewID != nil
            || session.composerReplyToCommentID != nil
    }
}

/// A review card with the threads submitted alongside it nested underneath,
/// indented behind a connecting rail so the relation reads like GitHub's.
private struct PullRequestActivityReviewGroupView: View {
    let entry: PullRequestActivityEntry
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel
    let onOpenFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PullRequestActivityEntryView(entry: entry, session: session, viewModel: viewModel)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.nestedThreads.enumerated()), id: \.offset) { _, thread in
                    PullRequestReviewThreadView(
                        thread: thread,
                        session: session,
                        viewModel: viewModel,
                        onOpenFiles: onOpenFiles
                    )
                }
            }
            .padding(.leading, 24)
            .overlay(alignment: .leading) {
                // An L: the horizontal foot marks where the review's threads end.
                PullRequestActivityRail()
                    .padding(.leading, 4)
            }
        }
    }
}

/// The nested-thread connecting rail: a vertical line down the leading edge that
/// turns into a horizontal foot along the bottom, so the hierarchy visibly ends.
///
/// The turn is the bottom-leading corner of the same continuous rounded rectangle
/// the thread cards draw, so both roundings read as one shape language. The other
/// three edges are pushed outside the clip, leaving only the L. A continuous
/// corner spreads about 1.53x its radius along each edge, which is why the rail
/// is wider than the turn's radius.
private struct PullRequestActivityRail: View {
    private static let cornerRadius = PullRequestReviewThreadView.cardCornerRadius
    /// Enough room for the whole turn plus the stroke inset, so the foot flattens
    /// out before the clip cuts it. The rail owns this rather than its caller
    /// because a narrower box would cut the turn mid-curve.
    private static let width: CGFloat = 20
    /// Pushes the trailing and top edges past the clip; any value beyond the
    /// rail's own bounds works.
    private static let overhang: CGFloat = 40

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 2)
            .padding(.top, -Self.overhang)
            .padding(.trailing, -Self.overhang)
            .clipped()
            .frame(width: Self.width)
    }
}

private struct PullRequestActivityEntryView: View {
    let entry: PullRequestActivityEntry
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel

    var body: some View {
        switch entry.kind {
        case .statusEvent(let event):
            statusEventRow(event)
        case .thread:
            // Rendered by `PullRequestPaneActivitySection`, which owns `onOpenFiles`.
            EmptyView()
        case .comment, .review:
            commentCard
        }
    }

    /// GitHub renders status changes as bare timeline rows, not comment cards.
    private func statusEventRow(_ event: PullRequestTimelineEvent) -> some View {
        HStack(alignment: .center, spacing: 6) {
            iconSlot

            PullRequestAvatarView(login: event.actorLogin, url: event.actorAvatarURL, loader: viewModel.avatarLoader)

            Text(event.actorLogin)
                .font(.caption.weight(.medium))

            // One line, ellipsized: commit phrases carry the full headline and
            // would otherwise wrap these bare rows to two lines.
            Text(Self.phrase(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if let date = entry.date {
                PullRequestTimestampLabel(date: date, referenceDate: viewModel.referenceDate)
            }
        }
        // Bare rows sit between padded cards; extra breathing room keeps the
        // 16pt stack rhythm from reading cramped around them. No horizontal
        // padding: the 16pt icon slot then spans the same column as the
        // Reviewers avatars above.
        .padding(.vertical, 6)
    }

    /// SF symbols size by font and vary in width while octicons are fixed
    /// frames; a shared slot keeps the avatar column aligned across every
    /// timeline row.
    private var iconSlot: some View {
        icon.frame(width: 16, alignment: .center)
    }

    /// Status glyphs reuse the tinted Primer Octicons so timeline state changes
    /// match the list's status iconography.
    private func octicon(_ name: String, tint: some ShapeStyle) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundStyle(tint)
    }

    /// GitHub's conversation phrasing for each bare timeline row.
    private static func phrase(for event: PullRequestTimelineEvent) -> String {
        switch event.kind {
        case .readyForReview:
            return "marked this pull request as ready for review"
        case .convertToDraft:
            return "marked this pull request as draft"
        case .closed:
            return "closed this pull request"
        case .reopened:
            return "reopened this pull request"
        case .merged:
            return "merged this pull request"
        case .commit:
            return event.detail.map { "added commit \($0)" } ?? "added a commit"
        case .forcePushed:
            return "force-pushed the head branch"
        case .reviewRequested:
            return event.detail.map { "requested a review from \($0)" } ?? "requested a review"
        case .reviewRequestRemoved:
            return event.detail.map { "removed the review request from \($0)" }
                ?? "removed a review request"
        }
    }

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                if hasVerdictIcon {
                    iconSlot
                }

                PullRequestCommentAuthorRow(
                    login: authorLine,
                    avatarURL: avatarURL,
                    isBot: isBot,
                    avatarLoader: viewModel.avatarLoader,
                    authorFont: .subheadline.weight(.medium),
                    authorIsProminent: true
                ) {
                    Spacer(minLength: 0)

                    if let date = entry.date {
                        PullRequestTimestampLabel(date: date, referenceDate: viewModel.referenceDate)
                    }

                    if let comment = actionableComment, !isEditingIssueComment {
                        PullRequestCommentActionsMenu(
                            onEdit: comment.viewerCanUpdate ? { viewModel.openIssueCommentEditor(comment) } : nil,
                            onDelete: comment.viewerCanDelete ? { viewModel.requestDeleteIssueComment(comment) } : nil
                        )
                    } else if let review = actionableReview, !isEditingReviewBody {
                        // Edit only: GitHub cannot delete a submitted review.
                        PullRequestCommentActionsMenu(
                            onEdit: { viewModel.openReviewBodyEditor(review) },
                            onDelete: nil
                        )
                    }
                }
            }

            if isEditingIssueComment || isEditingReviewBody {
                PullRequestActivityCommentEditor(session: session, viewModel: viewModel)
            } else if showsCardBody {
                PullRequestCommentBody(
                    markdown: bodyMarkdown,
                    nodeID: nodeID,
                    reactions: reactions,
                    viewModel: viewModel
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    /// The issue comment behind this card when the viewer can act on it — the
    /// same permission gate as thread comments (`viewerCanUpdate`/`viewerCanDelete`,
    /// never authorship). Review cards gate through `actionableReview` instead.
    private var actionableComment: PullRequestComment? {
        guard case .comment(let comment) = entry.kind,
              comment.databaseId != nil,
              comment.viewerCanUpdate || comment.viewerCanDelete else {
            return nil
        }
        return comment
    }

    /// Editing swaps the card body for the inline editor, keeping the author row.
    private var isEditingIssueComment: Bool {
        guard case .comment(let comment) = entry.kind,
              let databaseId = comment.databaseId else {
            return false
        }
        return session.composerIssueCommentID == databaseId
    }

    /// The review behind this card when the viewer may rewrite its summary body.
    /// Same permission gate as comments, but no delete — GitHub only deletes
    /// pending reviews, never submitted ones. Body-less review cards are bare
    /// headers (a verdict row or a thread-group header) and get no menu, like
    /// GitHub.
    private var actionableReview: PullRequestReview? {
        guard case .review(let review) = entry.kind,
              review.databaseId != nil,
              review.viewerCanUpdate,
              !PullRequestMarkdown.sanitized(review.bodyMarkdown).isEmpty else {
            return nil
        }
        return review
    }

    /// Review cards without a summary body render as bare headers: no body, no
    /// reaction affordance, no menu — matching GitHub's "commented"/verdict rows.
    /// Reactions that somehow exist on a body-less review still render.
    private var showsCardBody: Bool {
        guard case .review(let review) = entry.kind else {
            return true
        }
        return !PullRequestMarkdown.sanitized(review.bodyMarkdown).isEmpty || !review.reactions.isEmpty
    }

    private var isEditingReviewBody: Bool {
        guard case .review(let review) = entry.kind,
              let databaseId = review.databaseId else {
            return false
        }
        return session.composerReviewID == databaseId
    }

    private var avatarURL: URL? {
        switch entry.kind {
        case .comment(let comment):
            return comment.authorAvatarURL
        case .review(let review):
            return review.authorAvatarURL
        case .statusEvent(let event):
            return event.actorAvatarURL
        case .thread:
            return nil
        }
    }

    private var isBot: Bool {
        switch entry.kind {
        case .comment(let comment):
            return comment.isBot
        case .review(let review):
            return review.isBot
        case .statusEvent, .thread:
            return false
        }
    }

    private var nodeID: String? {
        switch entry.kind {
        case .comment(let comment):
            return comment.nodeID
        case .review(let review):
            return review.nodeID
        case .statusEvent, .thread:
            return nil
        }
    }

    private var reactions: [PullRequestCommentReaction] {
        switch entry.kind {
        case .comment(let comment):
            return comment.reactions
        case .review(let review):
            return review.reactions
        case .statusEvent, .thread:
            return []
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .comment, .thread:
            EmptyView()
        case .statusEvent(let event):
            switch event.kind {
            case .readyForReview:
                octicon("EyeOcticon", tint: .secondary)
            case .convertToDraft:
                octicon("PullRequestDraftOcticon", tint: .secondary)
            case .closed:
                octicon("PullRequestClosedOcticon", tint: Color.red)
            case .reopened:
                octicon("PullRequestOcticon", tint: Color.green)
            case .merged:
                octicon("PullRequestMergeOcticon", tint: Color("PullRequestMergedColor"))
            case .commit:
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .forcePushed:
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .reviewRequested:
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .reviewRequestRemoved:
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .review(let review):
            switch review.state {
            case .approved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            case .changesRequested:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            case .commented, .dismissed, .pending:
                EmptyView()
            }
        }
    }

    /// Only verdict-bearing review cards keep a header glyph; plain comment and
    /// review headers dropped the chat bubble as redundant beside the author row.
    private var hasVerdictIcon: Bool {
        guard case .review(let review) = entry.kind else {
            return false
        }
        switch review.state {
        case .approved, .changesRequested:
            return true
        case .commented, .dismissed, .pending:
            return false
        }
    }

    private var authorLine: String {
        switch entry.kind {
        case .statusEvent(let event):
            return event.actorLogin
        case .comment(let comment):
            return comment.authorLogin
        case .thread(let thread):
            return thread.comments.first?.authorLogin ?? ""
        case .review(let review):
            switch review.state {
            case .approved:
                return "\(review.authorLogin) approved"
            case .changesRequested:
                return "\(review.authorLogin) requested changes"
            case .dismissed:
                return "\(review.authorLogin) review dismissed"
            case .commented, .pending:
                return "\(review.authorLogin) commented"
            }
        }
    }

    private var bodyMarkdown: String {
        switch entry.kind {
        case .statusEvent, .thread:
            return ""
        case .comment(let comment):
            return comment.bodyMarkdown
        case .review(let review):
            return review.bodyMarkdown
        }
    }
}
