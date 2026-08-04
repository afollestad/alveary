import AgentCLIKit
import Foundation

/// A `propose_pr_review` call, as recorded durably in the transcript.
///
/// Live confirmation state — the loaded diff preview, the in-flight submission, GitHub's
/// refusals — comes from `PullRequestReviewProposalCoordinator`, never from this snapshot.
struct PullRequestReviewProposalWidgetContent: Equatable {
    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        /// The proposal was opened and is awaiting the user's confirmation.
        case pendingConfirmation
        /// The host tool refused the request outright.
        case failed
    }

    /// What the model proposed. The user may confirm a different verdict, which the outcome
    /// marker records.
    let event: PullRequestReviewEvent
    /// The pull request the call named, or the one its result echoed.
    let identifier: PullRequestIdentifier?
    let body: String?
    let pendingCommentCount: Int?
    let proposalID: String?
    let message: String?
    let status: Status
}

/// Pure parsing for `propose_pr_review`'s persisted input/output JSON.
enum PullRequestReviewProposalWidgetParsing {
    static func content(
        input: String?,
        output: String?,
        isError: Bool
    ) -> PullRequestReviewProposalWidgetContent? {
        guard let arguments = HostToolWidgetJSON.object(from: input),
              let event = HostToolWidgetJSON.string(arguments["event"])
                  .flatMap(PullRequestHostToolRequestParser.reviewEvent(from:)) else {
            // Without a verdict the card cannot say what confirming would do, so the call keeps
            // the generic tool row.
            return nil
        }
        let receipt = HostToolWidgetJSON.object(from: output).map(Receipt.init(object:))
        return PullRequestReviewProposalWidgetContent(
            event: event,
            // The request's own `url` is required by the schema, so it is the reliable source;
            // the receipt's echo confirms it once the call lands.
            identifier: receipt?.identifier ?? requestedIdentifier(in: arguments),
            body: HostToolWidgetJSON.string(arguments["body"]),
            pendingCommentCount: receipt?.pendingCommentCount,
            proposalID: receipt?.proposalID,
            message: receipt?.message ?? HostToolWidgetJSON.plainText(from: output),
            status: status(receipt: receipt, output: output, isError: isError)
        )
    }

    static func proposalID(fromOutput output: String?) -> String? {
        HostToolWidgetJSON.object(from: output).flatMap { Receipt(object: $0).proposalID }
    }
}

private extension PullRequestReviewProposalWidgetParsing {
    struct Receipt {
        let status: String?
        let proposalID: String?
        let identifier: PullRequestIdentifier?
        let pendingCommentCount: Int?
        let message: String?

        init(object: [String: AgentCLIKit.JSONValue]) {
            status = HostToolWidgetJSON.string(object["status"])
            proposalID = HostToolWidgetJSON.string(object["proposal_id"])
            pendingCommentCount = HostToolWidgetJSON.integer(object["pending_comment_count"])
            message = HostToolWidgetJSON.string(object["message"])
            identifier = HostToolWidgetJSON.string(object["repository"]).flatMap { repository in
                HostToolWidgetJSON.integer(object["number"]).flatMap {
                    PullRequestIdentifier(nameWithOwner: repository, number: $0)
                }
            }
        }
    }

    static func requestedIdentifier(in arguments: [String: AgentCLIKit.JSONValue]) -> PullRequestIdentifier? {
        HostToolWidgetJSON.string(arguments["url"]).flatMap(PullRequestURLParser.identifier(from:))
    }

    /// Providers surface a host tool's result differently: Claude emits
    /// `JSON.stringify(structuredContent)` while Codex emits the plain text fallback. Only an
    /// explicit error means failure — a result that will not parse still opened a proposal, which
    /// the transcript then resolves by conversation rather than by an id it never received.
    static func status(
        receipt: Receipt?,
        output: String?,
        isError: Bool
    ) -> PullRequestReviewProposalWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        if isError || receipt?.status == "error" {
            return .failed
        }
        return .pendingConfirmation
    }
}
