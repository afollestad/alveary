import Foundation
import SwiftData

extension ConversationViewModel {
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

    func existingConversationEventRecord(id: String) -> ConversationEventRecord? {
        (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first) ?? nil
    }
}
