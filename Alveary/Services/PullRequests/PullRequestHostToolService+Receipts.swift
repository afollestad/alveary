import AgentCLIKit
import Foundation

/// The exact-retry ledger shared by every non-idempotent pull request tool.
///
/// A provider may replay a call it never saw the result of. Posting to GitHub twice is visible to
/// everyone on the pull request, so every tool that publishes something records what it did and
/// replays that instead of acting again. The idempotent ones — resolve and unresolve — keep no
/// ledger, because their end state is its own record.
extension PullRequestHostToolService {
    func callIdentity(
        context: AgentCLIKit.AgentHostToolCallContext,
        source: HostToolCallSource,
        canonicalPayloadHash: String
    ) throws -> PullRequestHostToolCallIdentity {
        PullRequestHostToolCallIdentity(
            deduplicationKey: HostToolDeduplication.key(
                sourceConversationID: source.conversation.id,
                processToken: context.processToken,
                requestID: try requireRequestID(context),
                canonicalPayloadHash: canonicalPayloadHash
            ),
            processToken: context.processToken,
            requestDate: requestDate()
        )
    }

    func replayedReceipt(
        on sourceConversation: Conversation,
        identity: PullRequestHostToolCallIdentity
    ) throws -> PullRequestHostToolReceipt? {
        do {
            let receipt = try sourceConversation.pullRequestHostToolReceipt(
                matching: identity.deduplicationKey,
                currentProcessToken: identity.processToken,
                at: identity.requestDate
            )
            if modelContext.hasChanges {
                try modelContext.save()
            }
            return receipt
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    /// Saved on its own: a failed ledger write must not roll back — or appear to undo — something
    /// already published on GitHub.
    func persistReceipt(
        _ receipt: PullRequestHostToolReceipt,
        on sourceConversation: Conversation
    ) throws {
        do {
            try sourceConversation.recordPullRequestHostToolReceipt(receipt)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    /// A replay answers with what the original call returned, so the model reads the same outcome
    /// rather than a second one it might describe as a further change.
    func replayedResult(
        receipt: PullRequestHostToolReceipt,
        fields: [String: AgentCLIKit.JSONValue] = [:]
    ) -> AgentCLIKit.AgentHostToolResult {
        var content = fields
        content["status"] = .string(receipt.status)
        content["message"] = .string(receipt.message)
        if let threadNodeID = receipt.threadNodeID {
            content["thread_id"] = .string(threadNodeID)
        }
        if let proposalID = receipt.proposalID {
            content["proposal_id"] = .string(proposalID)
        }
        return AgentCLIKit.AgentHostToolResult(
            text: receipt.message,
            structuredContent: .object(content)
        )
    }

    func makeReceipt(
        identity: PullRequestHostToolCallIdentity,
        toolName: String,
        status: String,
        message: String,
        handle: PullRequestHostToolReceiptHandle = .none
    ) -> PullRequestHostToolReceipt {
        var threadNodeID: String?
        var proposalID: String?
        switch handle {
        case .none:
            break
        case .thread(let nodeID):
            threadNodeID = nodeID
        case .proposal(let id):
            proposalID = id
        }
        // `commentOutcomes` is always nil since the retired `add_pr_review_comments` tool stopped
        // writing it; the receipt field itself stays so ledgers written by earlier builds decode.
        return PullRequestHostToolReceipt(
            deduplicationKey: identity.deduplicationKey,
            toolName: toolName,
            status: status,
            message: message,
            threadNodeID: threadNodeID,
            commentOutcomes: nil,
            proposalID: proposalID,
            sourceProcessToken: identity.processToken.uuidString.lowercased(),
            createdAt: identity.requestDate
        )
    }
}
