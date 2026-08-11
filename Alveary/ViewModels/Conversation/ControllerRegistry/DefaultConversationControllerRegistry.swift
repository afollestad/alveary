import Foundation
import Observation

@MainActor
final class DefaultConversationControllerRegistry: ConversationControllerRegistry {
    typealias Factory = @MainActor (Conversation) -> ConversationViewModel
    typealias TerminalFlush = @MainActor (ConversationViewModel) async throws -> Void
    typealias TerminalFlushRetryWait = @MainActor () async -> Void
    typealias RuntimeSuspension = @MainActor (ConversationViewModel) async -> Void
    typealias RuntimeSuspensionVerification = @MainActor (ConversationViewModel) async -> Bool

    private let makeViewModel: Factory
    let flushTerminalRecords: TerminalFlush
    let terminalFlushRetryWait: TerminalFlushRetryWait
    let suspendRuntime: RuntimeSuspension
    let runtimeIsSuspended: RuntimeSuspensionVerification
    var entries: [ConversationControllerKey: ControllerEntry] = [:]
    var outcomeHubs: [ConversationControllerKey: OutcomeHub] = [:]

    init(
        makeViewModel: @escaping Factory,
        flushTerminalRecords: @escaping TerminalFlush = { try await $0.flushPendingSaveNow() },
        suspendRuntime: @escaping RuntimeSuspension = {
            await $0.agentsManager.suspendRuntime(conversationId: $0.conversation.id)
        },
        runtimeIsSuspended: @escaping RuntimeSuspensionVerification = {
            let agentsManager = $0.agentsManager
            return await agentsManager.isRuntimeSuspended(conversationId: $0.conversation.id)
        },
        terminalFlushRetryWait: @escaping TerminalFlushRetryWait = waitForConversationTerminalFlushRetry
    ) {
        self.makeViewModel = makeViewModel
        self.flushTerminalRecords = flushTerminalRecords
        self.suspendRuntime = suspendRuntime
        self.runtimeIsSuspended = runtimeIsSuspended
        self.terminalFlushRetryWait = terminalFlushRetryWait
    }

    func makeViewLease(for conversation: Conversation) -> ConversationControllerLease {
        makeLease(for: conversation, kind: .view)
    }

    func makeBackgroundLease(for conversation: Conversation) -> ConversationControllerLease {
        makeLease(for: conversation, kind: .background)
    }

    func makeBackgroundLease(
        for conversation: Conversation,
        defersAutomaticSuspension: Bool
    ) -> ConversationControllerLease {
        makeLease(
            for: conversation,
            kind: .background,
            defersAutomaticSuspension: defersAutomaticSuspension
        )
    }

    func controller(for key: ConversationControllerKey) -> ConversationViewModel? {
        entries[key]?.viewModel
    }

    func outcomes(for key: ConversationControllerKey) -> AsyncStream<ConversationControllerOutcome> {
        let subscriptionID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ConversationControllerOutcome.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        let hub = outcomeHub(for: key)
        hub.continuations[subscriptionID] = continuation
        if let current = hub.current {
            continuation.yield(current)
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeOutcomeSubscription(subscriptionID, for: key)
            }
        }
        return stream
    }

    func flushForTermination() -> [ConversationControllerFlushFailure] {
        var failures: [ConversationControllerFlushFailure] = []
        for (key, entry) in entries {
            entry.terminalMaintenanceTask?.cancel()
            entry.terminalMaintenanceTask = nil
            do {
                try entry.viewModel.flushPendingSaveSynchronously()
            } catch {
                failures.append(.init(key: key, message: error.localizedDescription))
            }
        }
        return failures
    }

    func invalidate(for key: ConversationControllerKey) {
        if let entry = entries.removeValue(forKey: key) {
            entry.invalidate()
        }
        if let hub = outcomeHubs.removeValue(forKey: key) {
            for continuation in hub.continuations.values {
                continuation.finish()
            }
        }
    }

    func invalidateAll() {
        let keys = Set(entries.keys).union(outcomeHubs.keys)
        for key in keys {
            invalidate(for: key)
        }
    }
}

@MainActor
private func waitForConversationTerminalFlushRetry() async {
    try? await Task.sleep(for: .milliseconds(250))
}

extension DefaultConversationControllerRegistry {
    func makeLease(
        for conversation: Conversation,
        kind: ConversationControllerLeaseKind,
        defersAutomaticSuspension: Bool = false
    ) -> ConversationControllerLease {
        let key = ConversationControllerKey(conversation: conversation)
        let entry = entry(for: conversation, key: key)
        let leaseID = UUID()
        entry.registerLease(
            id: leaseID,
            kind: kind,
            defersAutomaticSuspension: defersAutomaticSuspension
        )
        reconcile(for: key, entry: entry)

        return ConversationControllerLease(
            key: key,
            kind: kind,
            viewModel: entry.viewModel,
            defersAutomaticSuspension: defersAutomaticSuspension,
            setActive: { [weak self] isActive in
                self?.setLease(leaseID, active: isActive, for: key)
            },
            releaseLease: { [weak self] in
                self?.releaseLease(leaseID, for: key)
            },
            finalizeDeferredLease: { [weak self] beforeRelease in
                try await self?.finalizeDeferredLease(
                    leaseID,
                    for: key,
                    beforeRelease: beforeRelease
                )
            },
            makeOutcomeStream: { [weak self] in
                self?.outcomes(for: key) ?? AsyncStream { $0.finish() }
            }
        )
    }

    func entry(for conversation: Conversation, key: ConversationControllerKey) -> ControllerEntry {
        if let existing = entries[key] {
            return existing
        }

        let viewModel = makeViewModel(conversation)
        precondition(
            viewModel.conversation.id == key.conversationID,
            "Conversation controller factory returned a view model for a different conversation"
        )
        let entry = ControllerEntry(viewModel: viewModel)
        entries[key] = entry
        armObservation(for: key, entry: entry)
        return entry
    }

    func setLease(_ leaseID: UUID, active: Bool, for key: ConversationControllerKey) {
        guard let entry = entries[key] else {
            return
        }
        entry.setLease(id: leaseID, active: active)
        reconcile(for: key, entry: entry)
    }

    func releaseLease(_ leaseID: UUID, for key: ConversationControllerKey) {
        guard let entry = entries[key] else {
            return
        }
        entry.removeLease(id: leaseID)
        reconcile(for: key, entry: entry)
    }

    func finalizeDeferredLease(
        _ leaseID: UUID,
        for key: ConversationControllerKey,
        beforeRelease: DeferredControllerReleaseAction
    ) async throws {
        guard let entry = entries[key],
              entry.leaseDefersAutomaticSuspension(id: leaseID) else {
            return
        }
        let failedTerminalBoundarySequence = entry.pendingTerminals.first.flatMap { pending in
            pending.status == .failed ? pending.boundarySequence : nil
        }

        do {
            try await flushTerminalRecords(entry.viewModel)
        } catch {
            guard entries[key] === entry else {
                return
            }
            entry.viewModel.lastTurnError = "Couldn't save the completed conversation: \(error.localizedDescription)"
            throw error
        }

        if let failedTerminalBoundarySequence {
            await finishTerminalFlushSuccess(
                boundarySequence: failedTerminalBoundarySequence,
                for: key,
                entry: entry
            )
        }

        guard entries[key] === entry,
              entry.leaseDefersAutomaticSuspension(id: leaseID) else {
            return
        }
        discardResolvedDeferredInteractionTurnIfNeeded(entry, for: key)
        guard canFinalizeDeferredLease(entry) else {
            throw DeferredControllerFinalizationError.controllerNotQuiescent
        }

        guard try await suspendDeferredRuntime(entry, leaseID: leaseID, for: key) else {
            return
        }
        guard entries[key] === entry,
              entry.leaseDefersAutomaticSuspension(id: leaseID) else {
            return
        }
        // Runtime teardown is an async boundary where a final buffered interaction can still be
        // delivered. Keep the lease until its owner supersedes and durably flushes that state.
        discardResolvedDeferredInteractionTurnIfNeeded(entry, for: key)
        guard canFinalizeDeferredLease(entry) else {
            throw DeferredControllerFinalizationError.controllerNotQuiescent
        }
        try beforeRelease.perform()
        entry.needsSuspension = false
        entry.quiescenceMaintenanceFailed = false
        entry.removeLease(id: leaseID)
        clearTerminalSaveErrorIfResolved(for: entry)
        reconcile(for: key, entry: entry)
    }

    func suspendDeferredRuntime(
        _ entry: ControllerEntry,
        leaseID: UUID,
        for key: ConversationControllerKey
    ) async throws -> Bool {
        while true {
            await suspendRuntime(entry.viewModel)
            guard entries[key] === entry,
                  entry.leaseDefersAutomaticSuspension(id: leaseID) else {
                return false
            }
            let isSuspended = await runtimeIsSuspended(entry.viewModel)
            guard entries[key] === entry,
                  entry.leaseDefersAutomaticSuspension(id: leaseID) else {
                return false
            }
            if isSuspended {
                return true
            }
            await terminalFlushRetryWait()
            guard entries[key] === entry,
                  entry.leaseDefersAutomaticSuspension(id: leaseID) else {
                return false
            }
            discardResolvedDeferredInteractionTurnIfNeeded(entry, for: key)
            guard canFinalizeDeferredLease(entry) else {
                throw DeferredControllerFinalizationError.controllerNotQuiescent
            }
        }
    }

    func canFinalizeDeferredLease(_ entry: ControllerEntry) -> Bool {
        entry.controllerPhase == .idle &&
            !entry.hasActiveWork &&
            !entry.viewModel.hasPendingPersistence &&
            entry.trackedTurn == nil &&
            entry.pendingTerminals.isEmpty &&
            entry.terminalMaintenanceTask == nil
    }

    func armObservation(for key: ConversationControllerKey, entry: ControllerEntry) {
        withObservationTracking {
            _ = entry.observedState
        } onChange: { [weak self, weak entry] in
            Task { @MainActor [weak self, weak entry] in
                guard let self, let entry, self.entries[key] === entry else {
                    return
                }
                self.armObservation(for: key, entry: entry)
                self.reconcile(for: key, entry: entry)
            }
        }
    }

    func reconcile(for key: ConversationControllerKey, entry: ControllerEntry) {
        guard entries[key] === entry else {
            return
        }

        let hub = outcomeHub(for: key)
        captureTerminalBoundary(for: entry, hub: hub)
        reconcileOutcome(entry.controllerPhase, for: key, entry: entry, hub: hub)

        if entry.terminalMaintenanceTask == nil {
            if let pending = entry.pendingTerminals.first,
               pending.status == .pending || pending.status == .retryPending {
                startTerminalFlush(for: key, entry: entry, hub: hub)
            } else if entry.needsSuspension,
                      !entry.hasTerminalMaintenanceFailure {
                startQuiescenceMaintenanceIfPossible(for: key, entry: entry)
            }
        }

        entry.isInternallyRetained = entry.trackedTurn != nil ||
            entry.hasActiveWork ||
            entry.viewModel.hasPendingPersistence ||
            entry.terminalMaintenanceTask != nil ||
            !entry.pendingTerminals.isEmpty ||
            entry.needsSuspension ||
            entry.hasTerminalMaintenanceFailure
        entry.reconcileLifecycles()

        guard entry.canEvict else {
            return
        }
        entries.removeValue(forKey: key)
        entry.invalidate()
        pruneOutcomeHubIfUnused(for: key)
    }

    func captureTerminalBoundary(for entry: ControllerEntry, hub: OutcomeHub) {
        let snapshot = entry.observedState
        if let boundary = snapshot.terminalBoundary,
           boundary.sequence > entry.lastConsumedTerminalBoundarySequence {
            entry.lastConsumedTerminalBoundarySequence = boundary.sequence
            if boundary.wasVisible {
                if snapshot.hasNonterminalGoal {
                    entry.deferredGoalBoundary = boundary
                } else {
                    enqueueTerminal(boundary, for: entry, hub: hub)
                }
            }
        }

        if !snapshot.hasNonterminalGoal,
           let deferredBoundary = entry.deferredGoalBoundary {
            entry.deferredGoalBoundary = nil
            enqueueTerminal(deferredBoundary, for: entry, hub: hub)
        }
    }

    func enqueueTerminal(
        _ boundary: ConversationTerminalBoundary,
        for entry: ControllerEntry,
        hub: OutcomeHub
    ) {
        let trackedTurn = entry.trackedTurn ?? makeTrackedTurn(state: .active, hub: hub)
        entry.trackedTurn = nil
        entry.pendingTerminals.append(
            PendingControllerTerminal(
                boundarySequence: boundary.sequence,
                turn: trackedTurn.turn,
                preterminalState: trackedTurn.state,
                preterminalWasPublished: trackedTurn.wasPublished,
                terminalState: outcomeState(for: boundary.result)
            )
        )
    }

    func reconcileOutcome(
        _ phase: ControllerPhase,
        for key: ConversationControllerKey,
        entry: ControllerEntry,
        hub: OutcomeHub
    ) {
        switch phase {
        case .active:
            transitionToNonterminal(.active, for: key, entry: entry, hub: hub)
        case .hiddenActive, .idle:
            break
        case .waitingForApproval(let interactionID):
            transitionToNonterminal(
                .waitingForApproval(interactionID: interactionID),
                for: key,
                entry: entry,
                hub: hub
            )
        case .waitingForQuestion(let interactionID):
            transitionToNonterminal(
                .waitingForQuestion(interactionID: interactionID),
                for: key,
                entry: entry,
                hub: hub
            )
        }
    }

    func transitionToNonterminal(
        _ state: ConversationControllerOutcome.State,
        for key: ConversationControllerKey,
        entry: ControllerEntry,
        hub: OutcomeHub
    ) {
        let startsVisibleTurn = entry.trackedTurn == nil && state == .active
        var trackedTurn = entry.trackedTurn ?? makeTrackedTurn(state: state, hub: hub)
        trackedTurn.state = state
        entry.trackedTurn = trackedTurn
        if startsVisibleTurn {
            retryFailedMaintenanceOnNextVisibleTurn(for: entry)
        }
        publishTrackedTurnIfUnblocked(for: key, entry: entry, hub: hub)
    }

    func retryFailedMaintenanceOnNextVisibleTurn(for entry: ControllerEntry) {
        if let failedIndex = entry.pendingTerminals.firstIndex(where: { $0.status == .failed }) {
            entry.pendingTerminals[failedIndex].status = .retryPending
        }
        entry.quiescenceMaintenanceFailed = false
    }

    func makeTrackedTurn(
        state: ConversationControllerOutcome.State,
        hub: OutcomeHub
    ) -> TrackedControllerTurn {
        hub.nextEpoch &+= 1
        return TrackedControllerTurn(
            turn: ConversationControllerTurn(epoch: hub.nextEpoch),
            state: state,
            wasPublished: false
        )
    }

    func publishTrackedTurnIfUnblocked(
        for key: ConversationControllerKey,
        entry: ControllerEntry,
        hub: OutcomeHub
    ) {
        guard !entry.hasUnpublishedTerminal,
              var trackedTurn = entry.trackedTurn else {
            return
        }
        let outcome = ConversationControllerOutcome(turn: trackedTurn.turn, state: trackedTurn.state)
        guard hub.current != outcome else {
            trackedTurn.wasPublished = true
            entry.trackedTurn = trackedTurn
            return
        }
        publish(outcome, for: key, hub: hub)
        trackedTurn.wasPublished = true
        entry.trackedTurn = trackedTurn
    }

    func outcomeHub(for key: ConversationControllerKey) -> OutcomeHub {
        if let existing = outcomeHubs[key] {
            return existing
        }
        let hub = OutcomeHub()
        outcomeHubs[key] = hub
        return hub
    }

    func publish(
        _ outcome: ConversationControllerOutcome,
        for key: ConversationControllerKey,
        hub: OutcomeHub
    ) {
        hub.current = outcome
        for continuation in hub.continuations.values {
            continuation.yield(outcome)
        }
    }

    func removeOutcomeSubscription(_ subscriptionID: UUID, for key: ConversationControllerKey) {
        outcomeHubs[key]?.continuations.removeValue(forKey: subscriptionID)
        pruneOutcomeHubIfUnused(for: key)
    }

    func pruneOutcomeHubIfUnused(for key: ConversationControllerKey) {
        guard entries[key] == nil,
              let hub = outcomeHubs[key],
              hub.continuations.isEmpty,
              hub.current?.state.isTerminal != false else {
            return
        }
        outcomeHubs.removeValue(forKey: key)
    }
}
