protocol ConversationRuntimeStore {
    @MainActor func conversationState(for conversationId: String) -> ConversationState
}
