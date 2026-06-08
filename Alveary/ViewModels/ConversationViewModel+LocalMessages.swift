import AgentCLIKit

extension ConversationViewModel {
    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation
    ) -> ConversationEventRecord {
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: "message",
            role: "user",
            content: message,
            conversation: dbConversation
        )
        modelContext.insert(record)
        state.grouper.appendLocalUserMessage(id: record.id, text: message)

        if !dbConversation.isMain,
           dbConversation.customTitle == nil,
           let name = AgentSessionPreviewGenerator.preview(fromInitialPrompt: message) {
            dbConversation.title = name
        }

        scheduleSave()
        return record
    }
}
