import Foundation
import SwiftData

struct ScheduledTaskTerminalPersistenceRequest {
    let runID: PersistentIdentifier
    let conversationID: String
    let result: ScheduledTaskRunExecutionResult
    let finishedAt: Date
}

struct ScheduledTaskTerminalMutationSnapshot {
    let statusRawValue: String
    let lastError: String?
    let finishedAt: Date?
    let requiresFinalizationRecovery: Bool
    let presentationThread: AgentThread?
    let threadModifiedAt: Date?
    let conversationWasUnread: Bool

    init(run: ScheduledTaskRun, conversation: Conversation) {
        statusRawValue = run.statusRawValue
        lastError = run.lastError
        finishedAt = run.finishedAt
        requiresFinalizationRecovery = run.requiresFinalizationRecovery
        presentationThread = run.thread ?? run.targetThread
        threadModifiedAt = presentationThread?.modifiedAt
        conversationWasUnread = conversation.isUnread
    }

    func restore(run: ScheduledTaskRun, conversation: Conversation) {
        run.statusRawValue = statusRawValue
        run.lastError = lastError
        run.finishedAt = finishedAt
        run.requiresFinalizationRecovery = requiresFinalizationRecovery
        presentationThread?.modifiedAt = threadModifiedAt
        conversation.isUnread = conversationWasUnread
    }
}

@MainActor
func waitForScheduledTaskPersistenceRetry() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            continuation.resume()
        }
    }
}

@MainActor
extension DefaultScheduledTaskRunExecutor {
    func clearFinalizationRecoveryMarker(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.requiresFinalizationRecovery else {
            return
        }
        run.requiresFinalizationRecovery = false
        do {
            try saveFinalizationState()
        } catch {
            run.requiresFinalizationRecovery = true
            throw error
        }
    }
}
