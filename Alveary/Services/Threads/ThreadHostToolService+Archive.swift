import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// Archives a thread immediately. Reversible only from Alveary's Archived screen, which is
    /// why the instructions forbid describing it as deletion — and why no delete tool exists.
    ///
    /// Idempotent by design: archiving an already-archived thread succeeds rather than erroring,
    /// so a retry after a lost result reads as done instead of as a failure. That is also why this
    /// keeps no receipt ledger — the state itself is the ledger.
    func archiveThread(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        let source = try resolveMutatingSource(context: context)
        let threadID = try parseArchive(arguments: arguments)

        guard let conversation = modelContext.resolveConversation(conversationID: threadID),
              let thread = conversation.thread,
              !thread.isDraft else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        // Archiving kills the calling provider process mid-call, so the result would never be
        // delivered and the model would be left unsure whether it applied.
        guard thread.persistentModelID != source.thread.persistentModelID else {
            throw ThreadHostToolServiceError.cannotArchiveOwnThread
        }
        let name = thread.displayName()
        guard thread.archivedAt == nil else {
            return alreadyArchivedResult(threadID: threadID, name: name)
        }
        if let reason = lifecycleService.scheduledTaskAttachmentError(for: thread)?.localizedDescription {
            throw ThreadHostToolServiceError.threadCannotBeArchived(reason: reason)
        }

        let diagnostics: [ProviderSessionActionDiagnostic]
        do {
            diagnostics = try await lifecycleService.archiveThread(threadID: thread.persistentModelID)
        } catch let cleanupError as ThreadArchiveCleanupError {
            // The thread is archived; only its runtime teardown failed. Reporting an error here
            // would tell the model to retry something that already happened.
            return archivedResult(
                threadID: threadID,
                name: name,
                diagnostics: cleanupError.diagnostics,
                cleanupFailure: cleanupError.underlying.localizedDescription
            )
        }
        return archivedResult(threadID: threadID, name: name, diagnostics: diagnostics)
    }
}

private extension ThreadHostToolService {
    func archivedResult(
        threadID: String,
        name: String,
        diagnostics: [ProviderSessionActionDiagnostic],
        cleanupFailure: String? = nil
    ) -> AgentCLIKit.AgentHostToolResult {
        var message = "Archived the thread \"\(name)\". The user can restore it from Alveary's Archived screen; " +
            "it was not deleted."
        // Session diagnostics annotate the message; they never fail the tool, because the archive
        // itself already committed.
        for diagnostic in diagnostics {
            message += " \(diagnostic.toastMessage)"
        }
        if let cleanupFailure {
            message += " Runtime cleanup reported: \(cleanupFailure)"
        }
        return result(status: "archived", threadID: threadID, name: name, message: message)
    }

    func alreadyArchivedResult(threadID: String, name: String) -> AgentCLIKit.AgentHostToolResult {
        result(
            status: "already_archived",
            threadID: threadID,
            name: name,
            message: "The thread \"\(name)\" was already archived. Nothing changed."
        )
    }

    func result(
        status: String,
        threadID: String,
        name: String,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        AgentCLIKit.AgentHostToolResult(
            text: message,
            structuredContent: .object([
                "status": .string(status),
                "thread_id": .string(threadID),
                "name": .string(name),
                "message": .string(message)
            ])
        )
    }
}
