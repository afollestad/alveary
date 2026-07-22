import Foundation
import SwiftData

extension DefaultScheduledTaskRunExecutor {
    func markStarted(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            throw ScheduledTaskRunExecutionError.runMissing
        }
        run.status = .running
        run.startedAt = now()
        run.waitingAt = nil
        run.finishedAt = nil
        run.lastError = nil
        try saveExecutionState()
    }

    func persistedExecutionResult(
        for run: ScheduledTaskRun
    ) -> ScheduledTaskRunExecutionResult {
        switch run.decodedStatus {
        case .success:
            return .succeeded
        case .failure:
            return .failed(message: run.lastError)
        case .interrupted, .skipped:
            return .interrupted
        case .claimed, .preparing, .running, .waiting:
            preconditionFailure("Expected a terminal scheduled task run")
        case nil:
            preconditionFailure("Expected a known scheduled task run status")
        }
    }

    func persistenceRetryMessage(for error: Error) -> String {
        "Couldn't save the completed scheduled task: \(error.localizedDescription). Retrying."
    }

    func clearPersistenceRetryError(from viewModel: ConversationViewModel) {
        if viewModel.lastTurnError?.hasPrefix("Couldn't save the completed scheduled task:") == true {
            viewModel.lastTurnError = nil
        }
    }
}
