import Foundation
import SwiftData

enum ScheduledTaskRunExecutionResult: Equatable, Sendable {
    case succeeded
    case failed(message: String?)
    case interrupted
}

enum ScheduledTaskRunExecutionError: Error, Equatable, LocalizedError {
    case runMissing
    case conversationMissing
    case conversationDoesNotBelongToRun
    case invalidRunStatus(ScheduledTaskRunStatus)
    case alreadyExecuting

    var errorDescription: String? {
        switch self {
        case .runMissing:
            return "The scheduled task run no longer exists."
        case .conversationMissing:
            return "The scheduled task conversation no longer exists."
        case .conversationDoesNotBelongToRun:
            return "The scheduled task conversation is not linked to this run."
        case .invalidRunStatus(let status):
            return "The scheduled task run cannot start from its current status: \(status.rawValue)."
        case .alreadyExecuting:
            return "The scheduled task run is already executing."
        }
    }
}

@MainActor
protocol ScheduledTaskRunExecuting: AnyObject {
    func execute(_ materialization: ScheduledTaskRunMaterialization) async throws -> ScheduledTaskRunExecutionResult
    func execute(
        _ materialization: ScheduledTaskRunMaterialization,
        onUserStop: (@MainActor () async throws -> Void)?
    ) async throws -> ScheduledTaskRunExecutionResult
    func stop(runID: PersistentIdentifier) async throws
}

extension ScheduledTaskRunExecuting {
    func execute(
        _ materialization: ScheduledTaskRunMaterialization,
        onUserStop: (@MainActor () async throws -> Void)?
    ) async throws -> ScheduledTaskRunExecutionResult {
        try await execute(materialization)
    }
}
