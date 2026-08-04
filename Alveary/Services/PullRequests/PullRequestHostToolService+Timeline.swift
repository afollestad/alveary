import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// One pull request's conversation, chronologically.
    ///
    /// The interleaving is `PullRequestActivityEntry.entries(from:)`, the same merge the Overview
    /// renders, so the model reads the pull request in the order the user sees it. GitHub emits no
    /// "opened" timeline item, so it is synthesized from the pull request's own creation.
    func pullRequestTimeline(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let request = try parseTimeline(arguments: arguments)
        let detail = try await fetchDetail(request.identifier)

        let events = Self.events(from: detail)
        // The newest entries are the ones worth spending the budget on, but they read oldest-first
        // once the window is chosen.
        let shown = events.suffix(request.limit)

        return AgentCLIKit.AgentHostToolResult(
            text: listText(
                header: Self.header(detail: detail, shown: shown.count, total: events.count),
                rows: shown.map(\.textRow)
            ),
            structuredContent: .object([
                "repository": .string(detail.id.nameWithOwner),
                "number": .number(Double(detail.id.number)),
                "total_count": .number(Double(events.count)),
                "shown_count": .number(Double(shown.count)),
                "events": .array(shown.map(\.structuredRow))
            ])
        )
    }
}

/// One `get_pr_timeline` row, rendered identically into `structuredContent` and the text fallback.
private struct PullRequestHostToolTimelineRow {
    let type: String
    let actorLogin: String
    let actorAvatarURL: URL?
    let date: Date?
    var body: String?
    var bodyWasTruncated = false
    var reactions: [PullRequestCommentReaction] = []
    var verdict: String?
    var detail: String?
    var threadID: String?
    var path: String?
    var line: Int?
    var isResolved: Bool?
    var commentCount: Int?

    var structuredRow: AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "type": .string(type),
            "actor": PullRequestHostToolJSON.author(login: actorLogin, avatarURL: actorAvatarURL)
        ]
        if let date {
            row["at"] = .string(PullRequestHostToolDates.canonical(date))
        }
        if let body, !body.isEmpty {
            row["body_markdown"] = .string(body)
            row["body_truncated"] = .bool(bodyWasTruncated)
        }
        if !reactions.isEmpty {
            row["reactions"] = PullRequestHostToolJSON.reactions(reactions)
        }
        if let verdict {
            row["verdict"] = .string(verdict)
        }
        if let detail {
            row["detail"] = .string(detail)
        }
        if let threadID {
            row["thread_id"] = .string(threadID)
        }
        if let path {
            row["path"] = .string(path)
        }
        if let line {
            row["line"] = .number(Double(line))
        }
        if let isResolved {
            row["is_resolved"] = .bool(isResolved)
        }
        if let commentCount {
            row["comment_count"] = .number(Double(commentCount))
        }
        return .object(row)
    }

    var textRow: String {
        var parts = ["\(type) by \(actorLogin)"]
        if let verdict {
            parts.append(verdict)
        }
        if let path {
            parts.append(line.map { "\(path):\($0)" } ?? path)
        }
        if let isResolved {
            parts.append(isResolved ? "resolved" : "unresolved")
        }
        if let detail {
            parts.append(detail)
        }
        var row = "- \(parts.joined(separator: ", "))"
        if let body, !body.isEmpty {
            row += "\n  \(body.replacingOccurrences(of: "\n", with: "\n  "))"
        }
        return row
    }
}

private extension PullRequestHostToolService {
    static func header(detail: PullRequestDetail, shown: Int, total: Int) -> String {
        var header = "\(detail.id.displayKey) has \(total) timeline event(s)"
        if shown < total {
            header += ", showing the \(shown) most recent"
        }
        return header
    }

    /// Oldest first, with the synthesized "opened" row leading — every later entry is dated after
    /// the pull request existed.
    static func events(from detail: PullRequestDetail) -> [PullRequestHostToolTimelineRow] {
        var rows = [
            PullRequestHostToolTimelineRow(
                type: "opened",
                actorLogin: detail.authorLogin,
                actorAvatarURL: detail.authorAvatarURL,
                date: detail.createdAt
            )
        ]
        for entry in PullRequestActivityEntry.entries(from: detail) {
            rows.append(contentsOf: Self.rows(for: entry))
        }
        return rows
    }

    /// A review carrying threads renders as the review followed by its threads, matching how the
    /// Overview nests them under the review's card.
    static func rows(for entry: PullRequestActivityEntry) -> [PullRequestHostToolTimelineRow] {
        switch entry.kind {
        case .comment(let comment):
            return [commentRow(comment)]
        case .review(let review):
            return [reviewRow(review)] + entry.nestedThreads.map(threadRow)
        case .statusEvent(let event):
            return [statusRow(event)]
        case .thread(let thread):
            return [threadRow(thread)]
        }
    }

    static func commentRow(_ comment: PullRequestComment) -> PullRequestHostToolTimelineRow {
        let body = PullRequestHostToolJSON.truncated(
            comment.bodyMarkdown,
            limit: PullRequestHostToolLimits.maxBodyCharacters
        )
        return PullRequestHostToolTimelineRow(
            type: "comment",
            actorLogin: comment.authorLogin,
            actorAvatarURL: comment.authorAvatarURL,
            date: comment.createdAt,
            body: body.text,
            bodyWasTruncated: body.wasTruncated,
            reactions: comment.reactions
        )
    }

    static func reviewRow(_ review: PullRequestReview) -> PullRequestHostToolTimelineRow {
        let body = PullRequestHostToolJSON.truncated(
            review.bodyMarkdown,
            limit: PullRequestHostToolLimits.maxBodyCharacters
        )
        return PullRequestHostToolTimelineRow(
            type: "review",
            actorLogin: review.authorLogin,
            actorAvatarURL: review.authorAvatarURL,
            date: review.submittedAt,
            body: body.text,
            bodyWasTruncated: body.wasTruncated,
            reactions: review.reactions,
            verdict: verdictName(review.state)
        )
    }

    static func threadRow(_ thread: PullRequestReviewThread) -> PullRequestHostToolTimelineRow {
        let root = thread.comments.first
        let body = PullRequestHostToolJSON.truncated(
            root?.bodyMarkdown ?? "",
            limit: PullRequestHostToolLimits.maxBodyCharacters
        )
        return PullRequestHostToolTimelineRow(
            type: "review_thread",
            actorLogin: root?.authorLogin ?? "unknown",
            actorAvatarURL: root?.authorAvatarURL,
            date: root?.createdAt,
            body: body.text,
            bodyWasTruncated: body.wasTruncated,
            reactions: root?.reactions ?? [],
            threadID: thread.nodeID,
            path: thread.path,
            line: thread.line,
            isResolved: thread.isResolved,
            commentCount: thread.comments.count
        )
    }

    static func statusRow(_ event: PullRequestTimelineEvent) -> PullRequestHostToolTimelineRow {
        PullRequestHostToolTimelineRow(
            type: statusName(event.kind),
            actorLogin: event.actorLogin,
            actorAvatarURL: event.actorAvatarURL,
            date: event.createdAt,
            detail: event.detail
        )
    }

    /// A draft review has no verdict to report; `makeReviews` drops those, so this is the
    /// defensive branch rather than an expected one.
    static func verdictName(_ state: PullRequestReviewState) -> String? {
        switch state {
        case .approved:
            "approved"
        case .changesRequested:
            "changes_requested"
        case .commented:
            "commented"
        case .dismissed:
            "dismissed"
        case .pending:
            nil
        }
    }

    static func statusName(_ kind: PullRequestTimelineEvent.Kind) -> String {
        switch kind {
        case .readyForReview:
            "ready_for_review"
        case .convertToDraft:
            "converted_to_draft"
        case .closed:
            "closed"
        case .reopened:
            "reopened"
        case .merged:
            "merged"
        case .commit:
            "commit"
        case .forcePushed:
            "force_push"
        case .reviewRequested:
            "review_requested"
        case .reviewRequestRemoved:
            "review_request_removed"
        }
    }
}
