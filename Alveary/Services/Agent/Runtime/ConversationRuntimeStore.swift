protocol ConversationRuntimeStore {
    @MainActor func conversationState(for conversationId: String) -> ConversationState
    @MainActor func bindConversationState(_ state: ConversationState, for conversationId: String)
    @MainActor func setAutomatedScheduledRunActive(_ active: Bool, runID: String)
    @MainActor func isAutomatedScheduledRunActive(runID: String) -> Bool
    @MainActor func setAutomatedScheduledThreadActive(_ active: Bool, threadKey: String, runID: String)
    @MainActor func automatedScheduledRunID(threadKey: String) -> String?
}

extension ConversationRuntimeStore {
    @MainActor
    func setAutomatedScheduledThreadActive(_ active: Bool, threadKey: String, runID: String) {
        setAutomatedScheduledRunActive(active, runID: runID)
    }

    @MainActor
    func automatedScheduledRunID(threadKey: String) -> String? {
        nil
    }
}
