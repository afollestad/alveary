import Foundation
import SwiftData

/// Runtime teardown failed after the archive already committed. The thread is archived either
/// way, so the provider-session diagnostics gathered alongside it travel with the error rather
/// than being lost on the throw path.
struct ThreadArchiveCleanupError: Error {
    let diagnostics: [ProviderSessionActionDiagnostic]
    let underlying: Error
}

extension ThreadLifecycleService {
    /// Archives a thread and tears its runtime down, returning the provider-session diagnostics
    /// the caller should surface. `onPersistenceCommit` runs on the same turn as the durable save,
    /// before runtime teardown resumes, so a caller can route selection away from the archived row.
    @discardableResult
    func archiveThread(
        threadID: PersistentIdentifier,
        onPersistenceCommit: @escaping @MainActor () -> Void = {}
    ) async throws -> [ProviderSessionActionDiagnostic] {
        var dbThread = try requireThread(id: threadID)
        try requireNoScheduledTaskAttachment(dbThread)
        guard !dbThread.isDraft else {
            throw SidebarViewModelError.threadMissing
        }
        dbThread = try await quiesceScheduledTaskRunIfNeeded(for: dbThread)
        let snapshot = try makeThreadArchiveSnapshot(dbThread)
        let providerSessionResolution = await providerSessionActionService.resolveSessions(matching: snapshot.providerSessionAction)
        try backfillProviderSessionBindings(from: providerSessionResolution.records)
        if let currentThread = modelContext.resolveThread(id: snapshot.threadID) {
            try requireNoScheduledTaskAttachment(currentThread)
        }
        await beginConversationTeardowns(snapshot.conversationIDs)
        if let dbThread = modelContext.resolveThread(id: snapshot.threadID) {
            // Attachment state can change while provider resolution and runtime teardown await.
            // Recheck on the main actor immediately before the durable lifecycle mutation.
            try requireNoScheduledTaskAttachment(dbThread)
            if modelContext.hasChanges {
                try modelContext.save()
            }
            do {
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
        }
        notificationManager.forgetConversations(withIDs: snapshot.conversationIDs)
        invalidateConversationControllers(snapshot.conversationIDs)

        let teardownError = await conversationTeardownError(snapshot.conversationIDs)
        let diagnostics = await providerSessionActionService.archiveSessions(providerSessionResolution)
        if let teardownError {
            throw ThreadArchiveCleanupError(diagnostics: diagnostics, underlying: teardownError)
        }
        return diagnostics
    }
}
