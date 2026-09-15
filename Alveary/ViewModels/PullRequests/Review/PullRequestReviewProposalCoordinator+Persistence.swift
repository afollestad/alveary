import Foundation
import SwiftData

/// Local writes reread durable state because each window owns a separate editing context.
extension PullRequestReviewProposalCoordinator {
    func savedProposal(for presentation: PullRequestReviewProposalPresentation) -> PullRequestReviewProposalRecord? {
        let reader = ModelContext(modelContext.container)
        guard let conversation = reader.resolveConversation(conversationID: presentation.sourceConversationID),
              let record = try? conversation.pullRequestReviewProposal(), record.id == presentation.id else { return nil }
        return record
    }

    /// Re-reads the envelope before editing it — the proposal may have been resolved or superseded
    /// since the surface that asked for the edit rendered — and returns the stored replacement.
    /// `edit` returns nil to refuse.
    func rewriteProposal(
        presentation: PullRequestReviewProposalPresentation,
        _ edit: (PullRequestReviewProposalRecord) -> PullRequestReviewProposalRecord?
    ) -> PullRequestReviewProposalRecord? {
        let writer = ModelContext(modelContext.container)
        guard let conversation = writer.resolveConversation(conversationID: presentation.sourceConversationID),
              let record = try? conversation.pullRequestReviewProposal(), record.id == presentation.id,
              let updated = edit(record) else {
            return nil
        }
        do {
            try conversation.storePullRequestReviewProposal(updated)
            try writer.save()
            return updated
        } catch {
            writer.rollback()
            return nil
        }
    }

    /// Clears the envelope in its own save, ahead of the outcome marker's.
    func clearProposal(proposalID: String, conversationID: String) -> Bool {
        let writer = ModelContext(modelContext.container)
        guard let conversation = writer.resolveConversation(conversationID: conversationID) else {
            // The conversation is gone, so the proposal went with it.
            return true
        }
        guard (try? conversation.pullRequestReviewProposal())??.id == proposalID else {
            // Already resolved elsewhere; whichever path did it wrote the marker.
            return true
        }
        conversation.clearPullRequestReviewProposal()
        do {
            try writer.save()
            return true
        } catch {
            writer.rollback()
            return false
        }
    }
}

/// Body saves update other windows without the lifecycle notification's transcript regrouping.
extension PullRequestReviewProposalCoordinator {
    func notifySavedBodyChanged(proposalID: String) {
        notificationCenter.post(
            name: .reviewProposalCardStateChanged, object: self,
            userInfo: [ReviewProposalBodyChange.proposalIDKey: proposalID]
        )
    }

    func makeBodyChangeObservationTask() -> Task<Void, Never> {
        let notifications = notificationCenter.notifications(named: .reviewProposalCardStateChanged)
        return Task { @MainActor [weak self] in
            for await notification in notifications {
                guard !Task.isCancelled else { return }
                guard let self,
                      let source = notification.object as? PullRequestReviewProposalCoordinator, source !== self else { continue }
                refreshSharedSubmissionState()
                guard let proposalID = notification.userInfo?[ReviewProposalBodyChange.proposalIDKey] as? String,
                      presentations[proposalID] != nil else { continue }
                if refreshSavedProposal(proposalID: proposalID) { notifyChanged() }
            }
        }
    }
}

private enum ReviewProposalBodyChange {
    static let proposalIDKey = "savedReviewProposalBodyID"
}
