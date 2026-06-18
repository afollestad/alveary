import Foundation

extension ConversationEvent {
    @MainActor
    func taskListSnapshotRecord(conversation: Conversation) -> ConversationEventRecord {
        guard case let .taskListSnapshot(snapshot) = self else {
            preconditionFailure("Unexpected event case")
        }

        return ConversationEventRecord(
            conversationId: conversation.id,
            type: ConversationEventRecord.taskListType,
            content: snapshot.jsonString,
            conversation: conversation
        )
    }
}

extension ConversationTaskListSnapshot {
    static func decoded(from record: ConversationEventRecord) -> ConversationTaskListSnapshot? {
        guard record.type == ConversationEventRecord.taskListType,
              let content = record.content,
              let data = content.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ConversationTaskListSnapshot.self, from: data)
    }

    fileprivate var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
