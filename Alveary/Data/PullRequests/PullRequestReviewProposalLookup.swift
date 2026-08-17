import Foundation
import SwiftData

/// One conversation's pending review proposal, paired with the conversation that holds it.
///
/// The envelope stores no conversation id of its own — it *is* a column on `Conversation` — so a
/// cross-conversation reader has to carry the pairing itself.
struct PullRequestReviewProposalOwner {
    let conversationID: String
    let record: PullRequestReviewProposalRecord
}

/// Answers "what review proposal is pending for this pull request, anywhere" — the reverse of
/// `Conversation.pullRequestReviewProposal()`, which reads a single conversation's envelope.
///
/// The envelope lives inside a JSON column, so `#Predicate` cannot filter on its contents. The
/// descriptor narrows to conversations holding any proposal at all and the pure matcher decodes
/// only those, matching `PullRequestLinkedOwnerLookup`'s shape.
enum PullRequestReviewProposalLookup {
    static var proposalHoldingConversations: FetchDescriptor<Conversation> {
        FetchDescriptor(
            predicate: #Predicate { conversation in
                conversation.pullRequestReviewProposalJSON != nil
            }
        )
    }

    /// Every pending proposal, newest first.
    ///
    /// An envelope that fails to decode is skipped rather than thrown: one unreadable conversation
    /// must not hide every other pull request's proposal from a caller surveying all of them. The
    /// single-conversation read still throws, which is what keeps a proposal Alveary cannot
    /// understand from being silently replaced.
    static func proposals(in conversations: [Conversation]) -> [PullRequestReviewProposalOwner] {
        conversations
            .compactMap { conversation in
                guard let record = try? conversation.pullRequestReviewProposal() else {
                    return nil
                }
                return PullRequestReviewProposalOwner(
                    conversationID: conversation.id,
                    record: record
                )
            }
            .sorted { $0.record.createdAt > $1.record.createdAt }
    }

    /// The proposals pending against one pull request, newest first.
    static func proposals(
        in conversations: [Conversation],
        for identifier: PullRequestIdentifier
    ) -> [PullRequestReviewProposalOwner] {
        proposals(in: conversations).filter { $0.record.identifier == identifier }
    }
}
