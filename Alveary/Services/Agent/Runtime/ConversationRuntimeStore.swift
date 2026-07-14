protocol ConversationRuntimeStore {
    @MainActor func conversationState(for conversationId: String) -> ConversationState
    @MainActor func bindConversationState(_ state: ConversationState, for conversationId: String)
    @MainActor func setAutomatedScheduledRunActive(_ active: Bool, runID: String)
    @MainActor func isAutomatedScheduledRunActive(runID: String) -> Bool
}
