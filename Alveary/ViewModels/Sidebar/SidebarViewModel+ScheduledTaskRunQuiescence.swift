extension SidebarViewModel {
    typealias ScheduledTaskRunQuiescence = ThreadLifecycleService.ScheduledTaskRunQuiescence

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread) async throws -> AgentThread {
        try await threadLifecycle.quiesceScheduledTaskRunIfNeeded(for: thread)
    }

    func quiesceExactCallbacks(conversationID: String) async throws {
        try await threadLifecycle.quiesceExactCallbacks(conversationID: conversationID)
    }
}
