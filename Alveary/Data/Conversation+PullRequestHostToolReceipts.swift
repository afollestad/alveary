import Foundation

/// What one comment in a batch call produced, so a replay reports the same per-item rows —
/// including the ones a stopped batch never attempted.
struct PullRequestHostToolReceiptCommentOutcome: Codable, Equatable {
    let status: String
    var threadNodeID: String?
    var message: String?
}

/// What a mutating pull request tool call produced, kept so an exact retry replays it instead of
/// posting to GitHub twice. Maintenance is `HostToolReceiptLedger`'s.
struct PullRequestHostToolReceipt: HostToolReceiptRecord {
    let deduplicationKey: String
    /// The tool that produced it, so two tools sharing a ledger cannot replay each other.
    let toolName: String
    let status: String
    let message: String
    /// Feature-specific handles the replayed result echoes: a created thread's node id, a batch's
    /// per-comment outcomes, or a proposal's id. Optional because most tools need none of them,
    /// and because a receipt written before a field existed still has to decode.
    var threadNodeID: String?
    var commentOutcomes: [PullRequestHostToolReceiptCommentOutcome]?
    var proposalID: String?
    let sourceProcessToken: String
    let createdAt: Date
}

extension Conversation {
    func pullRequestHostToolReceipt(
        matching deduplicationKey: String,
        currentProcessToken: UUID,
        at date: Date
    ) throws -> PullRequestHostToolReceipt? {
        let stored: [PullRequestHostToolReceipt] = try HostToolReceiptLedger
            .decode(pullRequestHostToolReceiptsJSON)
        let receipts = HostToolReceiptLedger.maintained(
            stored,
            currentProcessToken: currentProcessToken.uuidString.lowercased(),
            at: date
        )
        if receipts != stored {
            pullRequestHostToolReceiptsJSON = try HostToolReceiptLedger.encode(receipts)
        }
        return receipts.first { $0.deduplicationKey == deduplicationKey }
    }

    func recordPullRequestHostToolReceipt(_ receipt: PullRequestHostToolReceipt) throws {
        let stored: [PullRequestHostToolReceipt] = try HostToolReceiptLedger
            .decode(pullRequestHostToolReceiptsJSON)
        let maintained = HostToolReceiptLedger.maintained(
            stored,
            currentProcessToken: receipt.sourceProcessToken,
            at: receipt.createdAt
        )
        let receipts = HostToolReceiptLedger.appending(receipt, to: maintained)
        guard receipts != stored else {
            return
        }
        pullRequestHostToolReceiptsJSON = try HostToolReceiptLedger.encode(receipts)
    }
}
