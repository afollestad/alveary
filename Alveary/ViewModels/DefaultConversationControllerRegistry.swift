import Foundation
import Observation

@MainActor
final class DefaultConversationControllerRegistry: ConversationControllerRegistry {
    typealias Factory = @MainActor (Conversation) -> ConversationViewModel
    typealias TerminalFlush = @MainActor (ConversationViewModel) async throws -> Void
    typealias RuntimeSuspension = @MainActor (ConversationViewModel) async -> Void

    private let makeViewModel: Factory
    let flushTerminalRecords: TerminalFlush
    let suspendRuntime: RuntimeSuspension
    var entries: [ConversationControllerKey: ControllerEntry] = [:]
    private var outcomeHubs: [ConversationControllerKey: OutcomeHub] = [:]

    init(
        makeViewModel: @escaping Factory,
        flushTerminalRecords: @escaping TerminalFlush = { try await $0.flushPendingSaveNow() },
        suspendRuntime: @escaping RuntimeSuspension = {
            await $0.agentsManager.suspendRuntime(conversationId: $0.conversation.id)
        }
    ) {
        self.makeViewModel = makeViewModel
        self.flushTerminalRecords = flushTerminalRecords
        self.suspendRuntime = suspendRuntime
    }

    func makeViewLease(for conversation: Conversation) -> ConversationControllerLease {
        makeLease(for: conversation, kind: .view)
    }

    func makeBackgroundLease(for conversation: Conversation) -> ConversationControllerLease {
        makeLease(for: conversation, kind: .background)
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

extension DefaultConversationControllerRegistry {
    func makeLease(
        for conversation: Conversation,
        kind: ConversationControllerLeaseKind
    ) -> ConversationControllerLease {
        let key = ConversationControllerKey(conversation: conversation)
        let entry = entry(for: conversation, key: key)
        let leaseID = UUID()
        entry.registerLease(id: leaseID, kind: kind)
        reconcile(for: key, entry: entry)

        return ConversationControllerLease(
            key: key,
            kind: kind,
            viewModel: entry.viewModel,
            setActive: { [weak self] isActive in
                self?.setLease(leaseID, active: isActive, for: key)
            },
            releaseLease: { [weak self] in
                self?.releaseLease(leaseID, for: key)
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
