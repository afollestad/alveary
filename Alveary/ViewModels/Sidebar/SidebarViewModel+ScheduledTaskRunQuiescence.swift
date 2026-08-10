extension SidebarViewModel {
    typealias ScheduledTaskRunQuiescence = ThreadLifecycleService.ScheduledTaskRunQuiescence

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread) async throws -> AgentThread {
        try await threadLifecycle.quiesceScheduledTaskRunIfNeeded(for: thread)
    }
}
