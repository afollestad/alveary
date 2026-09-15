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
    /// Stop may arrive during approval recovery, before this run owns any harness activity to cancel.
    private var preparingExecutionStopRequests: [PersistentIdentifier: Bool] = [:]

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
            execution.cancelHarnessTasks()
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
        let runID = materialization.runID
        guard activeExecutions[runID] == nil, preparingExecutionStopRequests[runID] == nil else {
            throw ScheduledTaskRunExecutionError.alreadyExecuting
        }
        let (run, conversation) = try resolveExecutionModels(materialization)
        let scheduledRunID = run.id
        preparingExecutionStopRequests[runID] = false
        defer { preparingExecutionStopRequests.removeValue(forKey: runID) }
        let conversationID = conversation.id
        let prompt = Self.outboundPrompt(for: materialization.prompt)
        let controllerKey = ConversationControllerKey(conversationID: conversationID)
        let lease = controllerRegistry.makeBackgroundLease(
            for: conversation,
            defersAutomaticSuspension: true
        )
        try await activateLeaseIfTargetIsReady(lease) {
            guard preparingExecutionStopRequests[runID] == false else { throw CancellationError() }
            return try resolveExecutionModels(materialization).0
        }
        preparingExecutionStopRequests.removeValue(forKey: runID)
        let baselineEpoch = controllerRegistry.currentOutcome(for: controllerKey)?.turn.epoch
        let execution = ActiveScheduledTaskExecution(
            runID: runID,
            lease: lease,
            conversationCancellationAction: conversationCancellationAction
        )
        activeExecutions[runID] = execution
        let userStopToken = lease.viewModel.installAutomatedScheduledUserStopHandler(onUserStop)
        defer { lease.viewModel.removeAutomatedScheduledUserStopHandler(token: userStopToken) }
        lease.viewModel.beginAutomatedScheduledRunExecution(runID: scheduledRunID)
        return try await executePreparedRun(execution, conversationID: conversationID, baselineEpoch: baselineEpoch, prompt: prompt)
    }

    func stop(runID: PersistentIdentifier) async throws {
        guard let execution = activeExecutions[runID] else {
            if preparingExecutionStopRequests[runID] != nil {
                preparingExecutionStopRequests[runID] = true
            }
            return
        }
        execution.isStopRequested = true
        execution.cancelHarnessTasks()
        await execution.cancelConversationActivity()
    }
}

private extension DefaultScheduledTaskRunExecutor {
    func executePreparedRun(
        _ execution: ActiveScheduledTaskExecution,
        conversationID: String,
        baselineEpoch: UInt64?,
        prompt: String
    ) async throws -> ScheduledTaskRunExecutionResult {
        do {
            let harnessResult = try await harnessExecutionResult(
                execution: execution,
                outcomes: execution.lease.outcomes(),
                baselineEpoch: baselineEpoch,
                prompt: prompt
            )
            let terminalRequest = ScheduledTaskTerminalPersistenceRequest(
                runID: execution.runID,
                conversationID: conversationID,
                result: harnessResult,
                finishedAt: now()
            )
            let persistedResult = try await finishRunDurably(
                terminalRequest,
                viewModel: execution.lease.viewModel,
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

    func harnessExecutionResult(
        execution: ActiveScheduledTaskExecution,
        outcomes: AsyncStream<ConversationControllerOutcome>,
        baselineEpoch: UInt64?,
        prompt: String
    ) async throws -> ScheduledTaskRunExecutionResult {
        let viewModel = execution.lease.viewModel
        let cancellationHandlerAction = self.cancellationHandlerAction
        let completion: ScheduledTaskRunExecutionResult = try await withTaskCancellationHandler {
            do {
                try await startHarnessTurn(
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
            let result = try await execution.runHarnessOutcomeConsumer {
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

    func startHarnessTurn(
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
        execution.registerHarnessStart(task, token: token)
        do {
            try await task.value
            execution.clearHarnessStart(token: token)
        } catch {
            execution.clearHarnessStart(token: token)
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
            userInfo: [AgentStatusChangedKey.conversationID: conversationID]
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
            // Parallel harness interactions can arrive while finalization is awaiting persistence
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
                // A non-quiescent controller is still doing work, such as a harness follow-up turn or
                // live background tasks; only persistence failures are worth a banner.
                if !(error is DeferredControllerFinalizationError) {
                    execution.lease.viewModel.lastTurnError = persistenceRetryMessage(for: error)
                }
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
