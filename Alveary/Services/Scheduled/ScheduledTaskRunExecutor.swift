import Foundation
import SwiftData

@MainActor
final class DefaultScheduledTaskRunExecutor: ScheduledTaskRunExecuting {
    typealias AutomatedTurnStarter = @MainActor (ConversationViewModel, String) async throws -> Void
    typealias ScheduledStartBoundary = @MainActor @Sendable () throws -> Void
    typealias RuntimeAwareAutomatedTurnStarter = @MainActor (
        ConversationViewModel,
        String,
        ScheduledStartBoundary
    ) async throws -> Void
    typealias DateProvider = @MainActor () -> Date
    typealias TerminalStateSaver = @MainActor () throws -> Void
    typealias FinalizationStateSaver = @MainActor () throws -> Void
    typealias PersistenceRetryWait = @MainActor () async -> Void
    typealias ConversationCancellationAction = ActiveScheduledTaskExecution.ConversationCancellationAction
    typealias CancellationHandlerAction = @MainActor (ActiveScheduledTaskExecution) async -> Void

    let modelContext: ModelContext
    private let controllerRegistry: any ConversationControllerRegistry
    private let notificationManager: any NotificationManager
    private let startAutomatedTurn: RuntimeAwareAutomatedTurnStarter
    let saveExecutionState: TerminalStateSaver
    private let saveTerminalState: TerminalStateSaver
    let saveFinalizationState: FinalizationStateSaver
    private let persistenceRetryWait: PersistenceRetryWait
    private let conversationCancellationAction: ConversationCancellationAction
    private let cancellationHandlerAction: CancellationHandlerAction
    let now: DateProvider
    private var activeExecutions: [PersistentIdentifier: ActiveScheduledTaskExecution] = [:]

    init(
        modelContext: ModelContext,
        controllerRegistry: any ConversationControllerRegistry,
        notificationManager: any NotificationManager,
        startAutomatedTurn: AutomatedTurnStarter? = nil,
        saveExecutionState: TerminalStateSaver? = nil,
        saveTerminalState: TerminalStateSaver? = nil,
        saveFinalizationState: FinalizationStateSaver? = nil,
        persistenceRetryWait: @escaping PersistenceRetryWait = waitForScheduledTaskPersistenceRetry,
        conversationCancellationAction: @escaping ConversationCancellationAction = { viewModel in
            await viewModel.cancelAutomatedScheduledConversationActivity()
        },
        cancellationHandlerAction: @escaping CancellationHandlerAction = { execution in
            execution.cancelProviderTasks()
        },
        now: @escaping DateProvider = Date.init
    ) {
        self.modelContext = modelContext
        self.controllerRegistry = controllerRegistry
        self.notificationManager = notificationManager
        if let startAutomatedTurn {
            self.startAutomatedTurn = { viewModel, prompt, markStarted in
                try markStarted()
                try await startAutomatedTurn(viewModel, prompt)
            }
        } else {
            self.startAutomatedTurn = { viewModel, prompt, markStarted in
                try await viewModel.startAutomatedScheduledTurn(
                    prompt,
                    onRuntimePrepared: markStarted
                )
            }
        }
        self.saveExecutionState = saveExecutionState ?? { try modelContext.save() }
        self.saveTerminalState = saveTerminalState ?? { try modelContext.save() }
        self.saveFinalizationState = saveFinalizationState ?? { try modelContext.save() }
        self.persistenceRetryWait = persistenceRetryWait
        self.conversationCancellationAction = conversationCancellationAction
        self.cancellationHandlerAction = cancellationHandlerAction
        self.now = now
    }

    func execute(_ materialization: ScheduledTaskRunMaterialization) async throws -> ScheduledTaskRunExecutionResult {
        try await execute(materialization, onUserStop: nil)
    }

    func execute(
        _ materialization: ScheduledTaskRunMaterialization,
        onUserStop: (@MainActor () async throws -> Void)?
    ) async throws -> ScheduledTaskRunExecutionResult {
        let (run, conversation) = try resolveExecutionModels(materialization)
        let runID = run.persistentModelID
        let conversationID = conversation.id
        let prompt = materialization.prompt
        let controllerKey = ConversationControllerKey(conversationID: conversationID)
        let baselineEpoch = controllerRegistry.currentOutcome(for: controllerKey)?.turn.epoch
        let lease = controllerRegistry.makeBackgroundLease(
            for: conversation,
            defersAutomaticSuspension: true
        )
        try activateLeaseIfTargetIsReady(lease, for: run)
        let execution = ActiveScheduledTaskExecution(
            runID: runID,
            lease: lease,
            conversationCancellationAction: conversationCancellationAction
        )
        activeExecutions[runID] = execution
        let userStopToken = lease.viewModel.installAutomatedScheduledUserStopHandler(onUserStop)
        defer { lease.viewModel.removeAutomatedScheduledUserStopHandler(token: userStopToken) }
        lease.viewModel.beginAutomatedScheduledRunExecution(runID: run.id)
        let outcomes = lease.outcomes()

        do {
            let providerResult = try await providerExecutionResult(
                execution: execution,
                outcomes: outcomes,
                baselineEpoch: baselineEpoch,
                prompt: prompt
            )
            let terminalRequest = ScheduledTaskTerminalPersistenceRequest(
                runID: runID,
                conversationID: conversationID,
                result: providerResult,
                finishedAt: now()
            )
            let persistedResult = try await finishRunDurably(
                terminalRequest,
                viewModel: lease.viewModel,
                execution: execution
            )
            await finalizeExecutionDurably(execution)
            publishTerminalNotification(persistedResult, conversationID: conversationID)
            return persistedResult
        } catch let executionError {
            return try await finishExecutionAfterError(
                executionError,
                execution: execution,
                conversationID: conversationID
            )
        }
    }

    func stop(runID: PersistentIdentifier) async throws {
        guard let execution = activeExecutions[runID] else {
            return
        }
        execution.isStopRequested = true
        execution.cancelProviderTasks()
        await execution.cancelConversationActivity()
    }
}

private extension DefaultScheduledTaskRunExecutor {
    func finishExecutionAfterError(
        _ error: Error,
        execution: ActiveScheduledTaskExecution,
        conversationID: String
    ) async throws -> ScheduledTaskRunExecutionResult {
        await execution.cancelConversationActivity()
        let result: ScheduledTaskRunExecutionResult = execution.isStopRequested || Task.isCancelled
            ? .interrupted
            : .failed(message: error.localizedDescription)
        let terminalRequest = ScheduledTaskTerminalPersistenceRequest(
            runID: execution.runID,
            conversationID: conversationID,
            result: result,
            finishedAt: now()
        )

        do {
            let persistedResult = try await finishRunDurably(
                terminalRequest,
                viewModel: execution.lease.viewModel,
                execution: execution
            )
            await finalizeExecutionDurably(execution)
            publishTerminalNotification(persistedResult, conversationID: conversationID)
            return persistedResult
        } catch {
            await finalizeExecutionDurably(execution)
            throw error
        }
    }

    func resolveExecutionModels(
        _ materialization: ScheduledTaskRunMaterialization
    ) throws -> (ScheduledTaskRun, Conversation) {
        let runID = materialization.runID
        guard activeExecutions[runID] == nil else {
            throw ScheduledTaskRunExecutionError.alreadyExecuting
        }
        guard let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            throw ScheduledTaskRunExecutionError.runMissing
        }
        guard run.status == .preparing else {
            throw ScheduledTaskRunExecutionError.invalidRunStatus(run.status)
        }
        guard let conversation = modelContext.resolveConversation(conversationID: materialization.conversationID) else {
            throw ScheduledTaskRunExecutionError.conversationMissing
        }
        guard let destination = run.decodedDestinationSnapshot else {
            throw ScheduledTaskRunExecutionError.conversationDoesNotBelongToRun
        }
        switch destination {
        case .newThread:
            guard conversation.thread?.scheduledTaskRun?.persistentModelID == runID else {
                throw ScheduledTaskRunExecutionError.conversationDoesNotBelongToRun
            }
        case .existingThread:
            guard run.targetThread?.persistentModelID == conversation.thread?.persistentModelID,
                  run.targetConversationIDSnapshot == conversation.id else {
                throw ScheduledTaskRunExecutionError.conversationDoesNotBelongToRun
            }
        }
        return (run, conversation)
    }

    func providerExecutionResult(
        execution: ActiveScheduledTaskExecution,
        outcomes: AsyncStream<ConversationControllerOutcome>,
        baselineEpoch: UInt64?,
        prompt: String
    ) async throws -> ScheduledTaskRunExecutionResult {
        let viewModel = execution.lease.viewModel
        let cancellationHandlerAction = self.cancellationHandlerAction
        let completion: ScheduledTaskRunExecutionResult = try await withTaskCancellationHandler {
            do {
                try await startProviderTurn(
                    execution: execution,
                    viewModel: viewModel,
                    prompt: prompt
                )
            } catch {
                if error is CancellationError || execution.isStopRequested || Task.isCancelled {
                    await execution.cancelConversationActivity()
                    return .interrupted
                }
                return .failed(message: error.localizedDescription)
            }

            if execution.isStopRequested || Task.isCancelled {
                await execution.cancelConversationActivity()
                return .interrupted
            }
            let result = try await execution.runProviderOutcomeConsumer {
                try await self.consumeOutcomes(
                    outcomes,
                    runID: execution.runID,
                    after: baselineEpoch
                )
            }
            if Task.isCancelled {
                await execution.cancelConversationActivity()
                return .interrupted
            }
            return result
        } onCancel: {
            Task { @MainActor in
                await cancellationHandlerAction(execution)
            }
        }

        if execution.isStopRequested || Task.isCancelled {
            await execution.cancelConversationActivity()
            return .interrupted
        }
        return completion
    }

    func startProviderTurn(
        execution: ActiveScheduledTaskExecution,
        viewModel: ConversationViewModel,
        prompt: String
    ) async throws {
        try Task.checkCancellation()
        let startAutomatedTurn = self.startAutomatedTurn
        let markStarted: ScheduledStartBoundary = {
            try self.markStarted(runID: execution.runID)
        }
        let token = UUID()
        let task = Task { @MainActor in
            try Task.checkCancellation()
            try await startAutomatedTurn(viewModel, prompt, markStarted)
        }
        execution.registerProviderStart(task, token: token)
        do {
            try await task.value
            execution.clearProviderStart(token: token)
        } catch {
            execution.clearProviderStart(token: token)
            throw error
        }
    }

    func consumeOutcomes(
        _ outcomes: AsyncStream<ConversationControllerOutcome>,
        runID: PersistentIdentifier,
        after baselineEpoch: UInt64?
    ) async throws -> ScheduledTaskRunExecutionResult {
        var turn: ConversationControllerTurn?
        for await outcome in outcomes {
            if let baselineEpoch,
               outcome.turn.epoch <= baselineEpoch {
                continue
            }
            if turn == nil {
                turn = outcome.turn
            }
            guard outcome.turn == turn else {
                continue
            }

            switch outcome.state {
            case .active:
                try markRunning(runID: runID)
            case .waitingForApproval, .waitingForQuestion:
                try markWaiting(runID: runID)
            case .terminal(.succeeded):
                return .succeeded
            case .terminal(.failed(let message)):
                return .failed(message: message)
            case .interrupted:
                return .interrupted
            }
        }

        return .interrupted
    }

    func markRunning(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let status = run.decodedStatus,
              !status.isTerminal,
              status != .running else {
            return
        }
        run.status = .running
        run.waitingAt = nil
        try saveExecutionState()
    }

    func markWaiting(runID: PersistentIdentifier) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              let status = run.decodedStatus,
              !status.isTerminal,
              status != .waiting else {
            return
        }
        run.status = .waiting
        run.waitingAt = now()
        try saveExecutionState()
    }

    func finishRunDurably(
        _ request: ScheduledTaskTerminalPersistenceRequest,
        viewModel: ConversationViewModel,
        execution: ActiveScheduledTaskExecution
    ) async throws -> ScheduledTaskRunExecutionResult {
        while true {
            await persistPreexistingContextChangesDurably(viewModel: viewModel)
            guard let run = modelContext.resolveScheduledTaskRun(id: request.runID) else {
                throw ScheduledTaskRunExecutionError.runMissing
            }
            guard let conversation = modelContext.resolveConversation(conversationID: request.conversationID) else {
                throw ScheduledTaskRunExecutionError.conversationMissing
            }
            let mutationSnapshot = ScheduledTaskTerminalMutationSnapshot(run: run, conversation: conversation)
            if run.hasKnownTerminalStatus {
                let persistedResult = persistedExecutionResult(for: run)
                let needsSave = !conversation.isUnread || !run.requiresFinalizationRecovery
                conversation.isUnread = true
                run.requiresFinalizationRecovery = true
                if !needsSave {
                    clearPersistenceRetryError(from: viewModel)
                    publishTerminalConversationChange(conversationID: request.conversationID)
                    return persistedResult
                }

                do {
                    try saveTerminalState()
                    clearPersistenceRetryError(from: viewModel)
                    publishTerminalConversationChange(conversationID: request.conversationID)
                    return persistedResult
                } catch {
                    mutationSnapshot.restore(run: run, conversation: conversation)
                    viewModel.lastTurnError = persistenceRetryMessage(for: error)
                    await persistenceRetryWait()
                    continue
                }
            }

            let effectiveResult: ScheduledTaskRunExecutionResult = execution.isStopRequested
                ? .interrupted
                : request.result
            applyTerminalResult(effectiveResult, finishedAt: request.finishedAt, to: run)
            conversation.isUnread = true
            do {
                try saveTerminalState()
                clearPersistenceRetryError(from: viewModel)
                publishTerminalConversationChange(conversationID: request.conversationID)
                return effectiveResult
            } catch {
                mutationSnapshot.restore(run: run, conversation: conversation)
                viewModel.lastTurnError = persistenceRetryMessage(for: error)
                await persistenceRetryWait()
            }
        }
    }

    func persistPreexistingContextChangesDurably(viewModel: ConversationViewModel) async {
        while modelContext.hasChanges {
            do {
                try modelContext.save()
                clearPersistenceRetryError(from: viewModel)
                return
            } catch {
                viewModel.lastTurnError = persistenceRetryMessage(for: error)
                await persistenceRetryWait()
            }
        }
    }

    func publishTerminalConversationChange(conversationID: String) {
        notificationManager.refreshBadgeCount()
        NotificationCenter.default.post(
            name: .agentStatusChanged,
            object: nil,
            userInfo: ["conversationId": conversationID]
        )
    }

    func publishTerminalNotification(
        _ result: ScheduledTaskRunExecutionResult,
        conversationID: String
    ) {
        switch result {
        case .succeeded:
            notificationManager.handleEvent(.stop(message: nil), conversationId: conversationID)
        case .failed(let message):
            notificationManager.handleEvent(.error(message: message ?? ""), conversationId: conversationID)
        case .interrupted:
            break
        }
    }

    func applyTerminalResult(
        _ result: ScheduledTaskRunExecutionResult,
        finishedAt: Date,
        to run: ScheduledTaskRun
    ) {
        switch result {
        case .succeeded:
            run.status = .success
            run.lastError = nil
        case .failed(let message):
            run.status = .failure
            run.lastError = message
        case .interrupted:
            run.status = .interrupted
            run.lastError = nil
        }
        run.finishedAt = finishedAt
        (run.thread ?? run.targetThread)?.modifiedAt = finishedAt
        run.requiresFinalizationRecovery = true
    }

    func finalizeExecutionDurably(_ execution: ActiveScheduledTaskExecution) async {
        await execution.sealConversationCancellation()
        while true {
            // Parallel provider interactions can arrive while finalization is awaiting persistence
            // or runtime teardown. Clear them again on every retry so a late prompt cannot retain
            // the controller and scheduled power indefinitely.
            await supersedeTerminalInteractionsAndDiscardRuntimeIfNeeded(
                execution.lease.viewModel
            )
            do {
                try await execution.lease.finalizeDeferredSuspension {
                    try self.clearFinalizationRecoveryMarker(runID: execution.runID)
                    self.clearPersistenceRetryError(from: execution.lease.viewModel)
                    execution.lease.viewModel.finishAutomatedScheduledRunExecution()
                }
                clearPersistenceRetryError(from: execution.lease.viewModel)
                break
            } catch {
                await supersedeTerminalInteractionsAndDiscardRuntimeIfNeeded(
                    execution.lease.viewModel
                )
                execution.lease.viewModel.lastTurnError = persistenceRetryMessage(for: error)
                await persistenceRetryWait()
            }
        }
        activeExecutions.removeValue(forKey: execution.runID)
    }

    func supersedeTerminalInteractionsAndDiscardRuntimeIfNeeded(
        _ viewModel: ConversationViewModel
    ) async {
        guard viewModel.supersedeAutomatedScheduledPendingInteractions() else {
            return
        }
        await viewModel.agentsManager.discardInactiveDeferredInteractionRuntime(
            conversationId: viewModel.conversation.id
        )
    }

}
