import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: String
    var title: String?
    var provider: String?
    var pendingRestoreContext: String?
    var isActive: Bool
    var isMain: Bool
    var displayOrder: Int
    var isUnread: Bool
    var thread: AgentThread?
    @Relationship(deleteRule: .cascade, inverse: \ConversationEventRecord.conversation) var events: [ConversationEventRecord]

    init(
        id: String = UUID().uuidString,
        title: String? = nil,
        provider: String? = nil,
        pendingRestoreContext: String? = nil,
        isActive: Bool = true,
        isMain: Bool = true,
        displayOrder: Int = 0,
        isUnread: Bool = false,
        thread: AgentThread? = nil,
        events: [ConversationEventRecord] = []
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.pendingRestoreContext = pendingRestoreContext
        self.isActive = isActive
        self.isMain = isMain
        self.displayOrder = displayOrder
        self.isUnread = isUnread
        self.thread = thread
        self.events = events
    }
}

extension Conversation {
    func refreshPendingRestoreContextFromHistory() {
        pendingRestoreContext = Self.buildPendingRestoreContext(
            from: events,
            conversationName: displayName()
        )
    }
}

private extension Conversation {
    static let restoreTranscriptEntryLimit = 6
    static let restoreToolActivityLimit = 3
    static let restoreLineCharacterLimit = 220
    static let restoreSummaryCharacterLimit = 2_400

    static func buildPendingRestoreContext(
        from events: [ConversationEventRecord],
        conversationName: String
    ) -> String? {
        let orderedEvents = events.sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        guard !orderedEvents.isEmpty else {
            return nil
        }

        let toolNamesByID: [String: String] = Dictionary(
            uniqueKeysWithValues: orderedEvents.compactMap { record in
                guard record.type == "tool_call",
                      let toolId = record.toolId,
                      let toolName = normalizedRestoreSnippet(record.toolName) else {
                    return nil
                }
                return (toolId, toolName)
            }
        )

        let transcriptEntries = Array(
            orderedEvents.compactMap(restoreTranscriptEntry).suffix(restoreTranscriptEntryLimit)
        )
        let toolEntries = Array(
            orderedEvents.compactMap { restoreToolActivityEntry(for: $0, toolNamesByID: toolNamesByID) }
                .suffix(restoreToolActivityLimit)
        )
        let finalNote = orderedEvents.reversed().compactMap(restoreSessionNote).first

        guard !transcriptEntries.isEmpty || !toolEntries.isEmpty || finalNote != nil else {
            return nil
        }

        var lines = [
            "Restoring context from local history.",
            "This is a fresh provider session; do not assume memory from earlier turns.",
            "Conversation: \(conversationName)"
        ]

        if !transcriptEntries.isEmpty {
            lines.append("Recent transcript:")
            lines.append(contentsOf: transcriptEntries)
        }

        if !toolEntries.isEmpty {
            lines.append("Recent tool activity:")
            lines.append(contentsOf: toolEntries)
        }

        if let finalNote {
            lines.append("Last session note:")
            lines.append("- \(finalNote)")
        }

        lines.append("Attach this as background context for the next user message and ask for clarification if anything important is missing.")
        return truncatedRestoreSummary(lines.joined(separator: "\n"))
    }

    static func restoreTranscriptEntry(for record: ConversationEventRecord) -> String? {
        guard record.type == "message",
              record.parentToolUseId == nil,
              let role = record.role,
              let content = normalizedRestoreSnippet(record.content) else {
            return nil
        }

        let speaker: String
        switch role {
        case "user":
            speaker = "User"
        case "assistant":
            speaker = "Assistant"
        default:
            return nil
        }

        return "- \(speaker): \(content)"
    }

    static func restoreToolActivityEntry(
        for record: ConversationEventRecord,
        toolNamesByID: [String: String]
    ) -> String? {
        guard record.type == "tool_result",
              record.parentToolUseId == nil else {
            return nil
        }

        let toolName = record.toolId.flatMap { toolNamesByID[$0] } ?? "Tool"
        let status: String
        if record.isError {
            status = "failed"
        } else if record.toolOutputInterrupted {
            status = "was interrupted"
        } else {
            status = "succeeded"
        }

        let detail = normalizedRestoreSnippet(record.toolOutputStderr)
            ?? normalizedRestoreSnippet(record.toolOutput)

        if let detail {
            return "- \(toolName): \(status). \(detail)"
        }
        return "- \(toolName): \(status)."
    }

    static func restoreSessionNote(for record: ConversationEventRecord) -> String? {
        switch record.type {
        case "tokens":
            guard record.isError else {
                return nil
            }
            return normalizedRestoreSnippet(record.stopReason) ?? "The previous run ended with an error."
        case "error", ConversationContextCompaction.failedType:
            return restoreErrorSessionNote(for: record)
        case "stop":
            return normalizedRestoreSnippet(record.content)
        case "notification":
            let type = normalizedRestoreSnippet(record.notificationType)
            let content = normalizedRestoreSnippet(record.content)
            switch (type, content) {
            case let (type?, content?):
                return "\(type): \(content)"
            case let (type?, nil):
                return type
            case let (nil, content?):
                return content
            default:
                return nil
            }
        default:
            return nil
        }
    }

    static func restoreErrorSessionNote(for record: ConversationEventRecord) -> String? {
        let note = normalizedRestoreSnippet(record.content)
        guard record.type == ConversationContextCompaction.failedType else {
            return note
        }
        return note.map { "Context compaction failed: \($0)" }
    }

    static func normalizedRestoreSnippet(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return nil
        }

        if collapsed.count > restoreLineCharacterLimit {
            return String(collapsed.prefix(restoreLineCharacterLimit - 3)) + "..."
        }
        return collapsed
    }

    static func truncatedRestoreSummary(_ summary: String) -> String {
        guard summary.count > restoreSummaryCharacterLimit else {
            return summary
        }

        return String(summary.prefix(restoreSummaryCharacterLimit - 3)) + "..."
    }
}
