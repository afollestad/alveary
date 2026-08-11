import Foundation

enum DeferredControllerFinalizationError: Error, LocalizedError {
    case controllerNotQuiescent

    var errorDescription: String? {
        "The completed conversation is still active and cannot be suspended yet."
    }
}

extension DefaultConversationControllerRegistry {
    func startTerminalFlush(
        for key: ConversationControllerKey,
        entry: ControllerEntry,
        hub: OutcomeHub
    ) {
        guard entry.terminalMaintenanceTask == nil,
              var pending = entry.pendingTerminals.first,
              pending.status == .pending || pending.status == .retryPending else {
            return
        }

        if !pending.preterminalWasPublished {
            publish(
                ConversationControllerOutcome(turn: pending.turn, state: pending.preterminalState),
                for: key,
                hub: hub
            )
            pending.preterminalWasPublished = true
            entry.pendingTerminals[0] = pending
        }

        let boundarySequence = pending.boundarySequence
        let retriesForAlreadyStartedTurn = pending.status == .pending
        let flushTerminalRecords = self.flushTerminalRecords
        entry.isInternallyRetained = true
        entry.reconcileLifecycles()
        entry.terminalMaintenanceTask = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else {
                return
            }
            do {
                try await flushTerminalRecords(entry.viewModel)
            } catch {
                if entry.defersAutomaticSuspension {
                    self.scheduleDeferredTerminalFlushRetry(
                        error,
                        boundarySequence: boundarySequence,
                        for: key,
                        entry: entry
                    )
                    return
                }
                self.finishTerminalFlushFailure(
                    error,
                    boundarySequence: boundarySequence,
                    retriesForAlreadyStartedTurn: retriesForAlreadyStartedTurn,
                    for: key,
                    entry: entry
                )
                return
            }
            await self.finishTerminalFlushSuccess(
                boundarySequence: boundarySequence,
                for: key,
                entry: entry
            )
        }
    }

    func scheduleDeferredTerminalFlushRetry(
        _ error: Error,
        boundarySequence: UInt64,
        for key: ConversationControllerKey,
        entry: ControllerEntry
    ) {
        guard entries[key] === entry,
              entry.pendingTerminals.first?.boundarySequence == boundarySequence else {
            return
        }
        entry.pendingTerminals[0].status = .retryPending
        entry.viewModel.lastTurnError = "Couldn't save the completed conversation: \(error.localizedDescription)"
        let retryWait = terminalFlushRetryWait
        entry.terminalMaintenanceTask = Task { @MainActor [weak self, weak entry] in
            await retryWait()
            guard !Task.isCancelled,
                  let self,
                  let entry,
                  self.entries[key] === entry,
                  entry.pendingTerminals.first?.boundarySequence == boundarySequence else {
                return
            }
            entry.terminalMaintenanceTask = nil
            self.reconcile(for: key, entry: entry)
        }
        reconcile(for: key, entry: entry)
    }

    func finishTerminalFlushFailure(
        _ error: Error,
        boundarySequence: UInt64,
        retriesForAlreadyStartedTurn: Bool,
        for key: ConversationControllerKey,
        entry: ControllerEntry
    ) {
        guard entries[key] === entry,
              entry.pendingTerminals.first?.boundarySequence == boundarySequence else {
            return
        }
        entry.terminalMaintenanceTask = nil
        let message = "Couldn't save the completed conversation: \(error.localizedDescription)"
        entry.viewModel.lastTurnError = message
        entry.pendingTerminals[0].status = retriesForAlreadyStartedTurn && entry.trackedTurn != nil
            ? .retryPending
            : .failed
        if !entry.pendingTerminals[0].terminalWasPublished {
            let turn = entry.pendingTerminals[0].turn
            entry.pendingTerminals[0].terminalWasPublished = true
            publish(
                .init(turn: turn, state: .terminal(.failed(message: message))),
                for: key,
                hub: outcomeHub(for: key)
            )
        }
        publishTrackedTurnIfUnblocked(for: key, entry: entry, hub: outcomeHub(for: key))
        reconcile(for: key, entry: entry)
    }

    func finishTerminalFlushSuccess(
        boundarySequence: UInt64,
        for key: ConversationControllerKey,
        entry: ControllerEntry
    ) async {
        guard entries[key] === entry,
              let pending = entry.pendingTerminals.first,
              pending.boundarySequence == boundarySequence else {
            return
        }
        entry.pendingTerminals.removeFirst()
        if !pending.terminalWasPublished {
            publish(
                .init(turn: pending.turn, state: pending.terminalState),
                for: key,
                hub: outcomeHub(for: key)
            )
        }
        clearTerminalSaveErrorIfResolved(for: entry)
        entry.needsSuspension = true
        publishTrackedTurnIfUnblocked(for: key, entry: entry, hub: outcomeHub(for: key))

        var runtimeWasSuspended = false
        if entry.pendingTerminals.isEmpty,
           canSuspend(entry) {
            runtimeWasSuspended = await suspendOrdinaryRuntimeUntilVerified(
                entry,
                for: key
            )
        }
        guard entries[key] === entry else {
            return
        }
        entry.terminalMaintenanceTask = nil
        entry.needsSuspension = !runtimeWasSuspended
        reconcile(for: key, entry: entry)
    }

    func startQuiescenceMaintenanceIfPossible(
        for key: ConversationControllerKey,
        entry: ControllerEntry
    ) {
        guard canSuspend(entry), entry.terminalMaintenanceTask == nil else {
            return
        }
        let flushTerminalRecords = self.flushTerminalRecords
        entry.terminalMaintenanceTask = Task { @MainActor [weak self, weak entry] in
            guard let self, let entry else {
                return
            }
            do {
                try await flushTerminalRecords(entry.viewModel)
            } catch {
                guard self.entries[key] === entry else {
                    return
                }
                entry.terminalMaintenanceTask = nil
                entry.quiescenceMaintenanceFailed = true
                entry.viewModel.lastTurnError = "Couldn't save the completed conversation: \(error.localizedDescription)"
                self.reconcile(for: key, entry: entry)
                return
            }

            guard self.entries[key] === entry else {
                return
            }
            var runtimeWasSuspended = false
            if self.canSuspend(entry) {
                runtimeWasSuspended = await self.suspendOrdinaryRuntimeUntilVerified(
                    entry,
                    for: key
                )
            }
            guard self.entries[key] === entry else {
                return
            }
            entry.terminalMaintenanceTask = nil
            entry.needsSuspension = !runtimeWasSuspended
            self.clearTerminalSaveErrorIfResolved(for: entry)
            self.reconcile(for: key, entry: entry)
        }
    }

    func suspendOrdinaryRuntimeUntilVerified(
        _ entry: ControllerEntry,
        for key: ConversationControllerKey
    ) async -> Bool {
        while !Task.isCancelled {
            guard entries[key] === entry,
                  canSuspend(entry) else {
                return false
            }
            await suspendRuntime(entry.viewModel)
            guard !Task.isCancelled,
                  entries[key] === entry,
                  canSuspend(entry) else {
                return false
            }

            let isSuspended = await runtimeIsSuspended(entry.viewModel)
            guard !Task.isCancelled,
                  entries[key] === entry,
                  canSuspend(entry) else {
                return false
            }
            if isSuspended {
                return true
            }

            await terminalFlushRetryWait()
        }
        return false
    }

    func discardResolvedDeferredInteractionTurnIfNeeded(
        _ entry: ControllerEntry,
        for key: ConversationControllerKey
    ) {
        guard entry.controllerPhase == .idle,
              !entry.hasActiveWork,
              !entry.viewModel.hasPendingPersistence,
              entry.pendingTerminals.isEmpty,
              entry.terminalMaintenanceTask == nil,
              let trackedTurn = entry.trackedTurn else {
            return
        }
        switch trackedTurn.state {
        case .waitingForApproval, .waitingForQuestion:
            // A provider can deliver a final interaction after the scheduled turn's terminal
            // boundary. Its owner has already superseded and flushed it before reaching here.
            publish(
                .init(turn: trackedTurn.turn, state: .interrupted),
                for: key,
                hub: outcomeHub(for: key)
            )
            entry.trackedTurn = nil
        case .active, .terminal, .interrupted:
            break
        }
    }

    func canSuspend(_ entry: ControllerEntry) -> Bool {
        !entry.defersAutomaticSuspension &&
            entry.controllerPhase == .idle &&
            !entry.hasActiveWork &&
            !entry.viewModel.hasPendingPersistence &&
            entry.trackedTurn == nil &&
            entry.pendingTerminals.isEmpty
    }

    func clearTerminalSaveErrorIfResolved(for entry: ControllerEntry) {
        guard !entry.hasTerminalMaintenanceFailure else {
            return
        }
        if entry.viewModel.lastTurnError?.hasPrefix("Couldn't save the completed conversation:") == true {
            entry.viewModel.lastTurnError = nil
        }
    }

    func outcomeState(
        for result: ConversationTerminalBoundary.Result
    ) -> ConversationControllerOutcome.State {
        switch result {
        case .succeeded:
            return .terminal(.succeeded)
        case .failed(let message):
            return .terminal(.failed(message: message))
        case .interrupted:
            return .interrupted
        }
    }
}
