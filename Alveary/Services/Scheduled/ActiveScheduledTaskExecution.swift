import Foundation
import SwiftData

@MainActor
final class ActiveScheduledTaskExecution {
    typealias ConversationCancellationAction = @MainActor (ConversationViewModel) async -> Void

    let runID: PersistentIdentifier
    let lease: ConversationControllerLease
    var isStopRequested = false
    private let conversationCancellationAction: ConversationCancellationAction
    private var providerStart: (token: UUID, task: Task<Void, Error>)?
    private var providerOutcomeConsumer: (
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

    func registerProviderStart(_ task: Task<Void, Error>, token: UUID) {
        precondition(providerStart == nil, "A scheduled provider start is already active")
        providerStart = (token, task)
    }

    func clearProviderStart(token: UUID) {
        guard providerStart?.token == token else {
            return
        }
        providerStart = nil
    }

    func registerProviderOutcomeConsumer(
        _ task: Task<ScheduledTaskRunExecutionResult, Error>,
        token: UUID
    ) {
        precondition(providerOutcomeConsumer == nil, "A scheduled provider outcome consumer is already active")
        providerOutcomeConsumer = (token, task)
    }

    func clearProviderOutcomeConsumer(token: UUID) {
        guard providerOutcomeConsumer?.token == token else {
            return
        }
        providerOutcomeConsumer = nil
    }

    func runProviderOutcomeConsumer(
        _ operation: @escaping @MainActor () async throws -> ScheduledTaskRunExecutionResult
    ) async throws -> ScheduledTaskRunExecutionResult {
        let token = UUID()
        let task = Task { @MainActor in
            try await operation()
        }
        registerProviderOutcomeConsumer(task, token: token)
        do {
            let result = try await task.value
            clearProviderOutcomeConsumer(token: token)
            return result
        } catch {
            clearProviderOutcomeConsumer(token: token)
            throw error
        }
    }

    func cancelProviderTasks() {
        providerStart?.task.cancel()
        providerOutcomeConsumer?.task.cancel()
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
