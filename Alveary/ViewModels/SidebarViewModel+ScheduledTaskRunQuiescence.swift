import SwiftData

extension SidebarViewModel {
    typealias ScheduledTaskRunQuiescence = @MainActor (PersistentIdentifier) async throws -> Void

    func quiesceScheduledTaskRunIfNeeded(for thread: AgentThread) async throws -> AgentThread {
        let threadID = thread.persistentModelID
        guard let run = thread.scheduledTaskRun else {
            return thread
        }
        let runID = run.persistentModelID

        try await stopAndWaitForScheduledTaskRun(runID)

        guard let currentThread = modelContext.resolveThread(id: threadID) else {
            throw SidebarViewModelError.threadMissing
        }
        if let currentRun = currentThread.scheduledTaskRun,
           !currentRun.hasKnownTerminalStatus {
            throw SidebarViewModelError.scheduledTaskRunStillActive
        }
        return currentThread
    }
}
