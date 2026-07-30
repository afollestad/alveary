import SwiftUI

/// Chronological conversation appended below the Overview content: issue comments
/// and reviews merged by date, followed by inline review threads.
struct PullRequestPaneActivitySection: View {
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
            ForEach(PullRequestActivityEntry.entries(from: detail)) { entry in
                if case .thread(let thread) = entry.kind {
                    PullRequestReviewThreadView(thread: thread, viewModel: viewModel, onOpenFiles: onOpenFiles)
                } else {
                    PullRequestActivityEntryView(entry: entry, viewModel: viewModel)
                }
            }
        }
    }
}

struct PullRequestActivityEntry: Identifiable {
    enum Kind {
        case comment(PullRequestComment)
        case review(PullRequestReview)
        case statusEvent(PullRequestTimelineEvent)
        case thread(PullRequestReviewThread)
    }

    let id: Int
    let date: Date?
    let kind: Kind

    static func entries(from detail: PullRequestDetail) -> [PullRequestActivityEntry] {
        var merged: [(date: Date?, kind: Kind)] = detail.comments.map { ($0.createdAt, .comment($0)) }
        // Body-less "commented" reviews are inline-comment carriers; their thread
        // content renders elsewhere, so a card here would be an empty shell.
        let visibleReviews = detail.reviews.filter { review in
            switch review.state {
            case .approved, .changesRequested, .dismissed:
                return true
            case .commented, .pending:
                return !PullRequestMarkdown.sanitized(review.bodyMarkdown).isEmpty || !review.reactions.isEmpty
            }
        }
        merged.append(contentsOf: visibleReviews.map { ($0.submittedAt, .review($0)) })
        merged.append(contentsOf: detail.timelineEvents.map { ($0.createdAt, .statusEvent($0)) })
        // Review threads interleave chronologically, dated by their root comment.
        merged.append(contentsOf: detail.reviewThreads.map { ($0.comments.first?.createdAt, .thread($0)) })
        let sorted = merged.sorted { lhs, rhs in
            (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
        }
        return sorted.enumerated().map { index, entry in
            PullRequestActivityEntry(id: index, date: entry.date, kind: entry.kind)
        }
    }
}

private struct PullRequestActivityEntryView: View {
    let entry: PullRequestActivityEntry
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

            Text(Self.phrase(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let date = entry.date {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PullRequestCommentBody(
                markdown: bodyMarkdown,
                nodeID: nodeID,
                reactions: reactions,
                viewModel: viewModel
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
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
    /// review headers dropped the chat bubble as redundant next to the author row.
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
                return "\(review.authorLogin) reviewed"
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

private struct PullRequestReviewThreadView: View {
    let thread: PullRequestReviewThread
    let viewModel: PullRequestsViewModel
    let onOpenFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(location)
                    .font(.caption.weight(.medium).monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                if thread.isResolved {
                    badge("Resolved", color: .green)
                }
                if thread.isOutdated {
                    // Orange, matching GitHub's outdated treatment.
                    badge("Outdated", color: .orange)
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
                VStack(alignment: .leading, spacing: 8) {
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
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PullRequestCommentBody(
                        markdown: comment.bodyMarkdown,
                        nodeID: comment.nodeID,
                        reactions: comment.reactions,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var location: String {
        if let line = thread.line {
            return "\(thread.path):\(line)"
        }
        return thread.path
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}
