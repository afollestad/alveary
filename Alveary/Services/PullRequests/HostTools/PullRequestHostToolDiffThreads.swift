import AgentCLIKit
import Foundation

/// Thread rendering shared by every resumable diff page.
enum PullRequestHostToolDiffThreads {
    static func structuredThread(
        _ thread: PullRequestReviewThread,
        commentAllowance: Int
    ) -> AgentCLIKit.JSONValue {
        let bounded = PullRequestHostToolJSON.boundedThreadComments(thread, limit: commentAllowance)
        var row: [String: AgentCLIKit.JSONValue] = [
            "is_resolved": .bool(thread.isResolved),
            "is_outdated": .bool(thread.isOutdated),
            "is_pending": .bool(thread.isPending),
            // GitHub takes no reply until a pending review is submitted, so saying so here keeps
            // the model from calling reply_to_pr_thread on a draft.
            "can_reply": .bool(thread.replyTargetCommentID != nil),
            "comment_count": .number(Double(thread.commentCount)),
            "comments": .array(bounded.comments.map(PullRequestHostToolJSON.comment)),
            "comments_truncated": .bool(bounded.wasTruncated)
        ]
        if let nodeID = thread.nodeID {
            row["thread_id"] = .string(nodeID)
        }
        if let line = thread.line {
            row["line"] = .number(Double(line))
        }
        let omissions = PullRequestHostToolText.threadOmissions(thread, limit: commentAllowance)
        let notes = [omissions.earlier, omissions.newer].compactMap { $0 }
        if !notes.isEmpty { row["comment_omissions"] = .array(notes.map { .string($0) }) }
        row["side"] = .string(thread.side.rawValue)
        return .object(row)
    }

}
