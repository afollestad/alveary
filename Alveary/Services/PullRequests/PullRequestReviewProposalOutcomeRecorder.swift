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
    /// Only legacy recovery may lack a body; an explicitly empty comment must be recorded as an empty string.
    static func record(
        proposalID: String,
        sourceConversationID: String,
        outcome: HostToolWidgetOutcome,
        submittedEvent: String? = nil,
        body: String?,
        published: PullRequestPublishedReview? = nil,
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
            content: HostToolWidgetOutcomeMarker.content(for: outcome, title: submittedEvent, body: body, published: published),
            toolId: proposalID,
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            timestamp: timestamp,
            conversation: conversation
        )
        modelContext.insert(record)
        save(modelContext)
    }

    /// Rewrites every marker holding the changed comment, forks' copies included, so a card that was not on
    /// screen when the change landed still shows it after the next transcript rebuild. Saves only on a change.
    static func apply(_ change: PullRequestReviewCommentChange, in modelContext: ModelContext) {
        let type = ConversationEventRecord.hostToolOutcomeType
        guard let markers = try? modelContext.fetch(FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { $0.type == type }
        )) else { return }
        var didChange = false
        for marker in markers {
            // Keyed rather than by node id, which JSON may escape (a legacy id's `/`); skips markers without a snapshot.
            guard let content = marker.content, content.contains("\"published\""),
                  let updated = HostToolWidgetOutcomeMarker.published(fromContent: content)?.applying(change),
                  let rewritten = HostToolWidgetOutcomeMarker.content(content, replacingPublished: updated) else { continue }
            marker.content = rewritten
            didChange = true
        }
        if didChange { save(modelContext) }
    }

    private static func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}
