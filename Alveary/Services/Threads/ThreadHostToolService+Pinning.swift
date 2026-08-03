import AgentCLIKit
import Foundation
import SwiftData

extension ThreadHostToolService {
    /// Pins or unpins a thread. Immediate and trivially reversible by its opposite tool, so there
    /// is no confirmation step and no receipt ledger — the pin state is its own record.
    func setThreadPinned(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue],
        isPinned: Bool
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        try flushPendingChanges()
        _ = try resolveMutatingSource(context: context)
        let threadID = try parseThreadIdentifier(arguments: arguments)

        guard let conversation = modelContext.resolveConversation(conversationID: threadID),
              let thread = conversation.thread,
              !thread.isDraft,
              thread.archivedAt == nil else {
            throw ThreadHostToolServiceError.threadNotFound
        }
        let name = thread.displayName()
        guard thread.isPinned != isPinned else {
            return pinResult(
                status: isPinned ? "already_pinned" : "already_unpinned",
                threadID: threadID,
                name: name,
                isPinned: thread.isPinned,
                message: "The thread \"\(name)\" was already \(isPinned ? "pinned" : "unpinned"). Nothing changed."
            )
        }

        let outcome = try lifecycleService.setThreadPinned(
            threadID: thread.persistentModelID,
            isPinned: isPinned
        )
        if outcome == .absorbedByPinnedProject {
            // Reporting success would be a lie — the pin would render nowhere.
            throw ThreadHostToolServiceError.threadAbsorbedByPinnedProject(
                projectName: thread.project?.name ?? "its project"
            )
        }
        return pinResult(
            status: isPinned ? "pinned" : "unpinned",
            threadID: threadID,
            name: name,
            isPinned: isPinned,
            message: isPinned
                ? "Pinned the thread \"\(name)\" to the top of Alveary's sidebar."
                : "Unpinned the thread \"\(name)\". It stays where it was; only its sidebar placement changed."
        )
    }
}

private extension ThreadHostToolService {
    func pinResult(
        status: String,
        threadID: String,
        name: String,
        isPinned: Bool,
        message: String
    ) -> AgentCLIKit.AgentHostToolResult {
        AgentCLIKit.AgentHostToolResult(
            text: message,
            structuredContent: .object([
                "status": .string(status),
                "thread_id": .string(threadID),
                "name": .string(name),
                "is_pinned": .bool(isPinned),
                "message": .string(message)
            ])
        )
    }
}
