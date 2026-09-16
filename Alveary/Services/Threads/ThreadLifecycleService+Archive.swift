import Foundation
import SwiftData

/// Runtime teardown failed after the archive already committed. The thread is archived either
/// way, so the harness-session diagnostics gathered alongside it travel with the error rather
/// than being lost on the throw path.
struct ThreadArchiveCleanupError: Error {
    let diagnostics: [HarnessSessionActionDiagnostic]
    let underlying: Error
}

extension ThreadLifecycleService {
    /// Archives a thread and tears its runtime down, returning the harness-session diagnostics
    /// the caller should surface. `onPersistenceCommit` runs on the same turn as the durable save,
    /// before runtime teardown resumes, so a caller can route selection away from the archived row.
    @discardableResult
    func archiveThread(
        threadID: PersistentIdentifier,
        onPersistenceCommit: @escaping @MainActor () -> Void = {}
    ) async throws -> [HarnessSessionActionDiagnostic] {
        var dbThread = try requireThread(id: threadID)
        try requireThreadLifecycleIsUnblocked(dbThread)
        guard !dbThread.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        dbThread = try await quiesceScheduledTaskRunIfNeeded(for: dbThread)
        let snapshot = try makeThreadArchiveSnapshot(dbThread)
        let harnessSessionResolution = await harnessSessionActionService.resolveSessions(matching: snapshot.harnessSessionAction)
        try backfillHarnessSessionBindings(from: harnessSessionResolution.records)
        if let currentThread = modelContext.resolveThread(id: snapshot.threadID) {
            try requireThreadLifecycleIsUnblocked(currentThread)
        }
        try await quiesceScheduledTaskRunIfNeeded(threadID: snapshot.threadID)
        await beginConversationTeardowns(snapshot.conversationIDs)
        try await quiesceScheduledTaskRunIfNeeded(threadID: snapshot.threadID)
        if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
            // Run state can change while harness resolution and runtime teardown await. Recheck
            // on the main actor immediately before the durable lifecycle mutation.
            try requireThreadLifecycleIsUnblocked(dbThread)
            try requireScheduledRunsQuiescent(dbThread)
            if modelContext.hasChanges {
                try modelContext.save()
            }
            var detachedScheduledTaskIDs: [String] = []
            var rejectedProposals: [PullRequestReviewProposalRejection] = []
            do {
                // Same save as `archivedAt`, while the row still carries the workspace the
                // surviving schedules inherit.
                detachedScheduledTaskIDs = ScheduledTaskTargetDetachment.detachTargets(of: dbThread)
                rejectedProposals = clearPullRequestReviewProposals(of: dbThread)
                dbThread.isPinned = false
                dbThread.pinnedSortOrder = nil
                dbThread.archivedAt = Date()
                _ = try SidebarOrderNormalization.normalize(in: modelContext)
                try modelContext.save()
                onPersistenceCommit()
                postThreadLifecycleChanged(threadID: snapshot.threadID, mode: snapshot.mode)
            } catch {
                modelContext.rollback()
                throw error
            }
            // After the commit that cleared them, never before: the marker's own transaction is what
            // keeps a failure here leaving the card unresolved rather than wrongly resolved.
            recordRejectedReviewProposals(rejectedProposals)
            postScheduledTasksDetached(definitionIDs: detachedScheduledTaskIDs)
        }
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)
        invalidateConversationControllers(snapshot.conversationIDs)

        let teardownError = await conversationTeardownError(snapshot.conversationIDs)
        let diagnostics = await harnessSessionActionService.archiveSessions(harnessSessionResolution)
        if let teardownError {
            throw ThreadArchiveCleanupError(diagnostics: diagnostics, underlying: teardownError)
        }
        return diagnostics
    }
}

/// One archived conversation's dismissed review proposal, carried from the clearing save to the
/// marker's own transaction.
private struct PullRequestReviewProposalRejection {
    let proposalID: String
    let conversationID: String
    let body: String
}

/// Archiving dismisses any review proposal the thread is holding.
///
/// The envelope survives archiving otherwise, and `PullRequestReviewProposalLookup` does not filter
/// archived threads — so the pull request pane would keep badging the staged comments "Proposed",
/// keep routing its composer into them, and keep offering a Submit for a card the user can no longer
/// reach from the sidebar. Deleting needs none of this: `AgentThread.conversations` cascades, so the
/// envelope goes with the row.
///
/// Split in two so the clear rides the archive's own save while the marker takes its own
/// transaction, the order `PullRequestReviewProposalOutcomeRecorder` documents.
extension ThreadLifecycleService {
    private func clearPullRequestReviewProposals(of thread: AgentThread) -> [PullRequestReviewProposalRejection] {
        thread.conversations.compactMap { conversation in
            guard let record = try? conversation.pullRequestReviewProposal() else {
                return nil
            }
            conversation.clearPullRequestReviewProposal()
            return PullRequestReviewProposalRejection(
                proposalID: record.id,
                conversationID: conversation.id,
                body: record.body ?? ""
            )
        }
    }

    private func recordRejectedReviewProposals(_ rejections: [PullRequestReviewProposalRejection]) {
        guard !rejections.isEmpty else {
            return
        }
        for rejection in rejections {
            PullRequestReviewProposalOutcomeRecorder.record(
                proposalID: rejection.proposalID,
                sourceConversationID: rejection.conversationID,
                outcome: .rejected,
                body: rejection.body,
                in: modelContext
            )
        }
        // Every window's coordinator reloads off this, which is what drops the proposal from the
        // pull request pane on the same turn.
        NotificationCenter.default.post(name: .pullRequestReviewProposalsChanged, object: nil)
    }
}
