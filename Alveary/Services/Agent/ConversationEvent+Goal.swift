import SwiftData

extension ConversationEvent {
    @MainActor
    func goalRecord(conversation: Conversation) -> ConversationEventRecord? {
        guard case let .goal(event) = self else {
            preconditionFailure("Unexpected event case")
        }

        let payload: ConversationGoalRecordPayload
        if event.isCleared {
            payload = .cleared(objective: event.objective)
        } else if let snapshot = event.snapshot {
            payload = .snapshot(snapshot)
        } else {
            return nil
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: ConversationEventRecord.goalType,
            content: payload.objective,
            toolInput: payload.encodedString,
            conversation: conversation
        )
    }
}
