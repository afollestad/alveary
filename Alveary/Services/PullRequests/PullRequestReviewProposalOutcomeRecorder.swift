import Foundation
import SwiftData

/// Writes the durable transcript marker that resolves a review-proposal widget.
///
/// The host-tool receipt on `Conversation` is a dedup ledger pruned by process token and retention
/// window, so it cannot carry history; the marker is a hidden `ConversationEventRecord` instead,
/// exactly as `ScheduledTaskProposalOutcomeRecorder` does for scheduling.
///
/// It is written in its own transaction, immediately after the one that cleared the proposal.
/// Failing between the two saves leaves the widget unresolved rather than wrongly resolved, which
/// is the safe direction when the alternative is a card claiming a review was submitted.
enum PullRequestReviewProposalOutcomeRecorder {
    static func record(
        proposalID: String,
        sourceConversationID: String,
        outcome: HostToolWidgetOutcome,
        submittedEvent: String? = nil,
        in modelContext: ModelContext,
        at timestamp: Date = .now
    ) {
        guard let conversation = modelContext.resolveConversation(conversationID: sourceConversationID) else {
            return
        }
        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: ConversationEventRecord.hostToolOutcomeType,
            // The verdict rides in `title`: the user may confirm a different one than the model
            // proposed, and the resolved card has to name what was actually submitted.
            content: HostToolWidgetOutcomeMarker.content(for: outcome, title: submittedEvent),
            toolId: proposalID,
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
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
