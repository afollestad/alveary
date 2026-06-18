import Foundation
import SwiftData

extension ConversationViewModel {
    func persistCodexSubAgentStartIfNeeded(for event: ConversationEvent) -> Bool {
        guard case .toolCall(let toolUseId, let name, let input, let parentToolUseId, let callerAgent) = event,
              name == "Agent",
              Self.isCodexSubAgentStartInput(input),
              let dbConversation = dbConversation() else {
            return false
        }

        let recordId = Self.codexSubAgentStartRecordId(conversationId: dbConversation.id, toolUseId: toolUseId)
        if existingConversationEventRecord(id: recordId) != nil {
            scheduleSave()
            return true
        }

        let record = ConversationEventRecord(
            id: recordId,
            conversationId: dbConversation.id,
            type: "tool_call",
            toolId: toolUseId,
            toolName: name,
            toolInput: input,
            parentToolUseId: parentToolUseId,
            callerAgent: callerAgent,
            conversation: dbConversation
        )
        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
        return true
    }

    func persistSubAgentCompletionMarker(for event: ConversationEvent) {
        guard case .subAgentCompleted(let toolUseId, let status, let toolUses, let totalTokens, let durationMs) = event else {
            return
        }
        guard let dbConversation = dbConversation() else {
            state.grouper.handleSubAgentControl(event)
            return
        }

        let recordId = Self.subAgentCompletionRecordId(conversationId: dbConversation.id, toolUseId: toolUseId)
        if existingConversationEventRecord(id: recordId) != nil {
            scheduleSave()
            return
        }

        let payload = SubAgentCompletionMarkerPayload(status: status, toolUses: toolUses, totalTokens: totalTokens)
        let content = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) }
        let record = ConversationEventRecord(
            id: recordId,
            conversationId: dbConversation.id,
            type: ConversationEventRecord.subAgentCompletedType,
            content: content,
            toolId: toolUseId,
            durationMs: durationMs,
            conversation: dbConversation
        )
        modelContext.insert(record)
        state.grouper.append(event: record)
        scheduleSave()
    }

    static func subAgentCompletionRecordId(conversationId: String, toolUseId: String) -> String {
        "sub-agent-completed:\(conversationId):\(toolUseId)"
    }

    static func codexSubAgentStartRecordId(conversationId: String, toolUseId: String) -> String {
        "codex-sub-agent-start:\(conversationId):\(toolUseId)"
    }

    func existingConversationEventRecord(id: String) -> ConversationEventRecord? {
        (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first) ?? nil
    }

    static func isCodexSubAgentStartInput(_ input: String) -> Bool {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["codex_collab_tool"] as? String else {
            return false
        }
        return normalizedCodexCollaborationTool(tool) == "spawnagent"
    }

    static func normalizedCodexCollaborationTool(_ tool: String) -> String {
        tool
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }
}
