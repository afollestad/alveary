import Foundation
import SwiftData

/// Identity a proposal outcome marker needs after its proposal row is gone.
struct ScheduledTaskProposalOutcomeTarget: Equatable, Sendable {
    let proposalID: String
    let sourceConversationID: String
    /// Target task name, captured before the proposal row is deleted so the marker can
    /// keep naming the task for providers whose tool result never carried a title.
    let title: String?

    init(proposal: ScheduledTaskProposal) {
        proposalID = proposal.id
        sourceConversationID = proposal.sourceConversationID
        title = proposal.targetTitleSnapshot ?? proposal.definitionDraft?.title
    }

    /// For actions applied without a proposal row; the receipt's deduplication key
    /// stands in as the correlation identity.
    init(proposalID: String, sourceConversationID: String, title: String?) {
        self.proposalID = proposalID
        self.sourceConversationID = sourceConversationID
        self.title = title
    }
}

/// Writes the durable transcript marker that resolves a scheduled-task proposal widget.
///
/// The host-tool receipt on `Conversation` is a dedup ledger pruned by process token and
/// retention window, so it cannot carry history; the marker is a hidden
/// `ConversationEventRecord` instead.
///
/// It is written in its own transaction, immediately after the one that consumed or
/// deleted the proposal. Inserting it alongside that mutation is not safe: those paths
/// roll back on failure, and rolling back a context that holds a freshly inserted record
/// next to a deleted model traps inside SwiftData. Failing between the two saves leaves
/// the widget unresolved rather than wrongly resolved, which is the safe direction.
enum ScheduledTaskProposalOutcomeRecorder {
    static func record(
        _ target: ScheduledTaskProposalOutcomeTarget,
        outcome: HostToolWidgetOutcome,
        definitionID: String? = nil,
        in modelContext: ModelContext,
        at timestamp: Date = .now
    ) {
        guard let conversation = modelContext.resolveConversation(conversationID: target.sourceConversationID) else {
            return
        }
        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: ConversationEventRecord.hostToolOutcomeType,
            content: HostToolWidgetOutcomeMarker.content(for: outcome, definitionID: definitionID, title: target.title),
            toolId: target.proposalID,
            toolName: HostToolTranscriptCatalog.toolName(ScheduledTaskHostToolCatalog.proposeToolName),
            timestamp: timestamp,
            conversation: conversation
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}
