import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// What is already staged for a pull request, from whichever conversation opened it.
    ///
    /// A proposal is a column on the conversation that proposed it, so an agentic review — which
    /// runs in a thread of its own — cannot see the card the user is looking at. Its own
    /// `propose_pr_review` supersedes that card, so without this read the model would replace
    /// staged comments it never knew about.
    ///
    /// Deliberately not gated on the calling conversation owning the proposal: the answer is about
    /// the pull request, and the thread asking is usually not the thread holding it.
    func pullRequestReviewProposal(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        guard let conversations = try? modelContext.fetch(
            PullRequestReviewProposalLookup.proposalHoldingConversations
        ) else {
            throw PullRequestHostToolServiceError.persistenceFailure
        }
        // Newest wins, matching how the pull request pane picks which card to render when more
        // than one somehow exists.
        let record = PullRequestReviewProposalLookup
            .proposals(in: conversations, for: identifier)
            .first?
            .record

        var fields: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(identifier.nameWithOwner),
            "number": .number(Double(identifier.number)),
            "has_proposal": .bool(record != nil)
        ]
        guard let record else {
            return AgentCLIKit.AgentHostToolResult(
                text: "No review proposal is waiting for confirmation on \(identifier.displayKey).",
                structuredContent: .object(fields)
            )
        }
        fields["event"] = .string(record.event)
        if let body = record.body {
            fields["body"] = .string(body)
        }
        if !record.stagedComments.isEmpty {
            fields["comments"] = .array(record.stagedComments.map(Self.commentField))
        }
        return AgentCLIKit.AgentHostToolResult(
            text: Self.reviewProposalMessage(record: record, identifier: identifier),
            structuredContent: .object(fields)
        )
    }
}

private extension PullRequestHostToolService {
    /// The shape `propose_pr_review` accepts, so carrying a comment forward is a copy. The anchor
    /// fingerprint stays out: it is Alveary's own bookkeeping, and re-proposing recaptures it from
    /// the diff that call validates against.
    static func commentField(_ comment: PullRequestReviewProposalRecord.Comment) -> AgentCLIKit.JSONValue {
        .object([
            "path": .string(comment.path),
            "line": .number(Double(comment.line)),
            "side": .string(comment.side),
            "body": .string(comment.body)
        ])
    }

    /// Codex persists the plain-text fallback rather than the structured content, so the text half
    /// has to carry the comments too — a model reading only this must still be able to pass them
    /// back.
    static func reviewProposalMessage(
        record: PullRequestReviewProposalRecord,
        identifier: PullRequestIdentifier
    ) -> String {
        var lines = [
            "A \(record.event) review of \(identifier.displayKey) is staged in Alveary, "
                + "waiting for the user to confirm it."
        ]
        if let body = record.body {
            lines.append("Summary: \(body)")
        }
        guard !record.stagedComments.isEmpty else {
            lines.append("It stages no inline comments.")
            return lines.joined(separator: "\n")
        }
        lines.append("It stages \(record.stagedComments.count) inline comment(s):")
        for comment in record.stagedComments {
            lines.append("- \(comment.path):\(comment.line) (\(comment.side)) — \(comment.body)")
        }
        return lines.joined(separator: "\n")
    }
}
