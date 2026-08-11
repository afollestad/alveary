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
        var shown = Array(events.suffix(request.limit))
        // The window decides how many threads are in this response, so the comment budget can
        // only be shared out once it is known.
        let allowance = PullRequestHostToolJSON.threadCommentAllowance(
            threadCount: shown.filter { $0.thread != nil }.count
        )
        for index in shown.indices {
            shown[index].commentAllowance = allowance
        }

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
    var isOutdated: Bool?
    /// The thread this row renders, carried whole so its conversation and true comment count
    /// travel together. Only thread rows have one, and they leave `body` nil in exchange — the
    /// root comment is `comments[0]`, so filling both would send it twice.
    var thread: PullRequestReviewThread?
    /// How many of that conversation to render, shared across the whole response.
    var commentAllowance = PullRequestHostToolLimits.maxThreadComments

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
        if let isOutdated {
            row["is_outdated"] = .bool(isOutdated)
        }
        if let thread {
            let bounded = PullRequestHostToolJSON.boundedThreadComments(thread, limit: commentAllowance)
            // GitHub's `totalCount`, never `comments.count`: `comments` is a page, so the array's
            // size would tell the model a thread was fully read when the newest replies never
            // arrived. `comments_truncated` covers the fetch cap as well as the cap above.
            row["comment_count"] = .number(Double(thread.commentCount))
            row["comments"] = .array(bounded.comments.map(PullRequestHostToolJSON.comment))
            row["comments_truncated"] = .bool(bounded.wasTruncated)
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
        if isOutdated == true {
            parts.append("outdated")
        }
        if let detail {
            parts.append(detail)
        }
        var row = "- \(parts.joined(separator: ", "))"
        if let thread {
            let lines = PullRequestHostToolText.threadCommentLines(thread, indent: "  ", limit: commentAllowance)
            if !lines.isEmpty {
                row += "\n" + lines.joined(separator: "\n")
            }
        } else if let body, !body.isEmpty {
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

    /// The whole conversation, not just its root. A thread's replies are where it says whether
    /// the point was answered, argued, or left open — reading only the first comment made a
    /// settled thread look outstanding and an answered one look unanswered.
    static func threadRow(_ thread: PullRequestReviewThread) -> PullRequestHostToolTimelineRow {
        let root = thread.comments.first
        return PullRequestHostToolTimelineRow(
            type: "review_thread",
            actorLogin: root?.authorLogin ?? "unknown",
            actorAvatarURL: root?.authorAvatarURL,
            date: root?.createdAt,
            threadID: thread.nodeID,
            path: thread.path,
            line: thread.line,
            isResolved: thread.isResolved,
            isOutdated: thread.isOutdated,
            thread: thread
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
