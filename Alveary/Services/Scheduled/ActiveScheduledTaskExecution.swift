import Foundation
import SwiftData

@MainActor
final class ActiveScheduledTaskExecution {
    typealias ConversationCancellationAction = @MainActor (ConversationViewModel) async -> Void

    let runID: PersistentIdentifier
    let lease: ConversationControllerLease
    var isStopRequested = false
    private let conversationCancellationAction: ConversationCancellationAction
    private var harnessStart: (token: UUID, task: Task<Void, Error>)?
    private var harnessOutcomeConsumer: (
        token: UUID,
        task: Task<ScheduledTaskRunExecutionResult, Error>
    )?
    private var conversationCancellationTask: Task<Void, Never>?
    private var isConversationCancellationSealed = false

    init(
        runID: PersistentIdentifier,
        lease: ConversationControllerLease,
        conversationCancellationAction: @escaping ConversationCancellationAction
    ) {
        self.runID = runID
        self.lease = lease
        self.conversationCancellationAction = conversationCancellationAction
    }

    func registerHarnessStart(_ task: Task<Void, Error>, token: UUID) {
        precondition(harnessStart == nil, "A scheduled harness start is already active")
        harnessStart = (token, task)
    }

    func clearHarnessStart(token: UUID) {
        guard harnessStart?.token == token else {
            return
        }
        harnessStart = nil
    }

    func registerHarnessOutcomeConsumer(
        _ task: Task<ScheduledTaskRunExecutionResult, Error>,
        token: UUID
    ) {
        precondition(harnessOutcomeConsumer == nil, "A scheduled harness outcome consumer is already active")
        harnessOutcomeConsumer = (token, task)
    }

    func clearHarnessOutcomeConsumer(token: UUID) {
        guard harnessOutcomeConsumer?.token == token else {
            return
        }
        harnessOutcomeConsumer = nil
    }

    func runHarnessOutcomeConsumer(
        _ operation: @escaping @MainActor () async throws -> ScheduledTaskRunExecutionResult
    ) async throws -> ScheduledTaskRunExecutionResult {
        let token = UUID()
        let task = Task { @MainActor in
            try await operation()
        }
        registerHarnessOutcomeConsumer(task, token: token)
        do {
            let result = try await task.value
            clearHarnessOutcomeConsumer(token: token)
            return result
        } catch {
            clearHarnessOutcomeConsumer(token: token)
            throw error
        }
    }

    func cancelHarnessTasks() {
        harnessStart?.task.cancel()
        harnessOutcomeConsumer?.task.cancel()
    }

    /// Coalesces stop and structured-execution cleanup into one retained barrier. Keeping the
    /// completed task prevents a late cancellation callback from targeting a manual follow-up.
    func cancelConversationActivity() async {
        if let conversationCancellationTask {
            await conversationCancellationTask.value
            return
        }
        guard !isConversationCancellationSealed else {
            return
        }

        let action = conversationCancellationAction
        let viewModel = lease.viewModel
        let task = Task { @MainActor in
            await action(viewModel)
        }
        conversationCancellationTask = task
        await task.value
    }

    /// Closes the cleanup registration boundary and drains work accepted before the seal.
    func sealConversationCancellation() async {
        isConversationCancellationSealed = true
        await conversationCancellationTask?.value
    }
}
