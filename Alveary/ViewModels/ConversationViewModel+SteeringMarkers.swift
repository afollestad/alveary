extension ConversationViewModel {
    func shouldPersistSteeredConversation(inputID: String) -> Bool {
        guard let localUserMessage = userMessageRecord(id: inputID) else { return false }
        return localUserMessage.conversationId == conversation.id &&
            localUserMessage.type == "message" &&
            localUserMessage.role == "user" &&
            existingConversationEventRecord(id: "steering-\(inputID)") == nil
    }
}
