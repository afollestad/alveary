extension ConversationViewModel {
    @discardableResult
    func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        shouldAutoNameThread: Bool
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

        if dbConversation.customTitle == nil,
           let name = Self.threadName(from: message) {
            dbConversation.title = name
        }

        if shouldAutoNameThread,
           let thread = dbConversation.thread,
           thread.isEffectivelyUntitled,
           let name = Self.threadName(from: message) {
            thread.name = name
        }

        scheduleSave()
        return record
    }
}
