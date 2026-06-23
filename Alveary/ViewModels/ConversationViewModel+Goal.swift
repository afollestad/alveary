import AgentCLIKit
import Foundation
import SwiftData

extension ConversationViewModel {
    var visibleGoalSnapshot: AgentGoalSnapshot? {
        state.visibleGoalSnapshot()
    }

    var hasVisibleUserMessageHistory: Bool {
        visibleUserMessageRecord() != nil
    }

    func hydrateGoalState(from events: [ConversationEventRecord]) {
        let runtimeGoal = state.goalSnapshot
        let goalRecords = events
            .filter { $0.type == ConversationEventRecord.goalType }
            .sorted { lhs, rhs in
                (lhs.timestamp, lhs.id) < (rhs.timestamp, rhs.id)
            }
        guard !goalRecords.isEmpty else {
            persistGoalSnapshotIfNeeded(runtimeGoal)
            return
        }

        var nextGoal: AgentGoalSnapshot?
        var dismissedKeys: Set<String> = []
        var lastRecordKey: String?
        var decodedGoalRecord = false
        for record in goalRecords {
            guard let payload = ConversationGoalRecordPayload.decode(from: record.toolInput) else {
                continue
            }
            decodedGoalRecord = true
            lastRecordKey = payload.encodedString
            switch payload.kind {
            case .snapshot:
                if let snapshot = payload.snapshot {
                    nextGoal = snapshot
                    if !snapshot.status.isTerminal {
                        dismissedKeys.removeAll()
                    }
                }
            case .cleared:
                nextGoal = nil
            case .terminalDismissal:
                if let snapshotKey = payload.snapshotKey {
                    dismissedKeys.insert(snapshotKey)
                }
            }
        }
        state.goalSnapshot = nextGoal
        state.dismissedTerminalGoalKeys = dismissedKeys
        state.lastPersistedGoalRecordKey = lastRecordKey
        if !decodedGoalRecord {
            state.goalSnapshot = runtimeGoal
        }
        persistGoalSnapshotIfNeeded(state.goalSnapshot)
    }

    func handleGoalEvent(_ event: AgentGoalEvent) -> Bool {
        let payload: ConversationGoalRecordPayload
        if event.isCleared {
            state.goalSnapshot = nil
            state.goalActionError = nil
            state.dismissedTerminalGoalKeys.removeAll()
            payload = .cleared(objective: event.objective)
        } else if let snapshot = event.snapshot {
            state.goalSnapshot = snapshot
            state.goalActionError = nil
            if !snapshot.status.isTerminal {
                state.dismissedTerminalGoalKeys.removeAll()
            }
            payload = .snapshot(snapshot)
        } else {
            return false
        }

        let recordKey = payload.encodedString
        guard recordKey != state.lastPersistedGoalRecordKey else {
            return false
        }
        state.lastPersistedGoalRecordKey = recordKey
        return true
    }

    func dismissTerminalGoalStatus() {
        guard let goal = state.goalSnapshot,
              goal.status.isTerminal else {
            return
        }
        let payload = ConversationGoalRecordPayload.terminalDismissal(snapshot: goal)
        guard let encodedPayload = payload.encodedString,
              let dbConversation = dbConversation() else {
            return
        }
        state.dismissedTerminalGoalKeys.insert(goal.stableGoalKey)
        state.lastPersistedGoalRecordKey = encodedPayload
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: ConversationEventRecord.goalType,
            content: goal.objective,
            toolInput: encodedPayload,
            conversation: dbConversation
        )
        modelContext.insert(record)
        scheduleSave()
    }

    func persistGoalSnapshotIfNeeded(_ snapshot: AgentGoalSnapshot?) {
        guard let snapshot,
              !(snapshot.status.isTerminal && state.dismissedTerminalGoalKeys.contains(snapshot.stableGoalKey)),
              let payload = ConversationGoalRecordPayload.snapshot(snapshot).encodedString,
              payload != state.lastPersistedGoalRecordKey,
              let dbConversation = dbConversation() else {
            return
        }
        state.lastPersistedGoalRecordKey = payload
        let record = ConversationEventRecord(
            conversationId: dbConversation.id,
            type: ConversationEventRecord.goalType,
            content: snapshot.objective,
            toolInput: payload,
            conversation: dbConversation
        )
        modelContext.insert(record)
        scheduleSave()
    }

    func performGoalAction(_ action: AgentGoalAction) async throws {
        guard let goal = state.goalSnapshot,
              !goal.status.isTerminal else {
            let message = "No active goal is available."
            state.goalActionError = message
            throw AgentError.spawnFailed(message)
        }
        guard goal.availableActions.contains(action) else {
            let message = "Goal \(action.rawValue) is not supported by this agent."
            state.goalActionError = message
            throw AgentError.spawnFailed(message)
        }
        state.goalActionError = nil
        do {
            try await agentsManager.performGoalAction(action, conversationId: conversation.id)
        } catch {
            state.goalActionError = error.localizedDescription
            throw error
        }
    }

    func setGoalModeArmed(_ isArmed: Bool) {
        if isArmed {
            guard state.goalSnapshot?.status.isTerminal != false else {
                lastTurnError = "A goal is already active."
                return
            }
        }
        state.isGoalModeArmed = isArmed
    }

    func disarmGoalModeIfNeeded() {
        guard state.isGoalModeArmed else {
            return
        }
        state.isGoalModeArmed = false
    }

    func startGoal(
        _ objective: String,
        supportsExistingSessionGoalStart: Bool = false
    ) async throws {
        let trimmedObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateGoalStartAvailability(trimmedObjective)

        do {
            if hasVisibleUserMessageHistory {
                guard supportsExistingSessionGoalStart else {
                    throw AgentError.spawnFailed("This agent can only start Goal mode before the first visible user message.")
                }
                try await startExistingSessionGoal(trimmedObjective)
            } else {
                try await startFirstMessageGoal(trimmedObjective)
            }
            state.isGoalModeArmed = false
        } catch {
            if lastTurnError == nil {
                lastTurnError = error.localizedDescription
            }
            throw error
        }
    }

    func visibleUserMessageRecord() -> ConversationEventRecord? {
        let conversationID = conversation.id
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { record in
                record.conversationId == conversationID &&
                    record.type == "message" &&
                    record.role == "user"
            },
            sortBy: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.id)
            ]
        )
        return try? modelContext.fetch(descriptor).first
    }
}

private extension ConversationViewModel {
    func validateGoalStartAvailability(_ trimmedObjective: String) throws {
        guard !trimmedObjective.isEmpty else {
            throw AgentError.spawnFailed("Provide a goal before starting Goal mode.")
        }
        guard state.goalSnapshot?.status.isTerminal != false else {
            throw AgentError.spawnFailed("A goal is already active.")
        }
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Send or clear queued messages before starting Goal mode.")
        }
        guard !state.isAwaitingHandoffSteering else {
            throw AgentError.spawnFailed("Complete session handoff steering before starting Goal mode.")
        }
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied.")
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Another message is already being sent.")
        }
        guard !isAgentActivelyWorking else {
            throw AgentError.spawnFailed("Wait for the current turn to finish before starting Goal mode.")
        }
    }

    func startFirstMessageGoal(_ objective: String) async throws {
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try await deliverMessageReserved(
                objective,
                initialGoal: objective,
                failureHandling: .removeAttempt
            )
        }
    }

    func startExistingSessionGoal(_ objective: String) async throws {
        try await applyPendingSessionSettingsBeforeNextOutboundTurn()
        try await withOutboundReservation {
            try repairMissingWorktreeIfNeeded()
            try await setupHiddenInitialRuntimeIfNeeded()
            if let recoveryContext = try await prepareRuntimeForOutbound(settingsSource: .nextTurn) {
                let resolvedContext = resolveSessionRecoveryStagedContext(
                    recoveryContext: recoveryContext,
                    stagedContextOverride: nil,
                    useCurrentStagedContextWhenOverrideNil: true
                )
                state.stagedContext = resolvedContext.stagedContext
            }

            state.lastTurnInterrupted = false
            state.isCancellingTurn = false
            state.activeRuntimeActivityTurnId = nil
            state.pendingSyntheticAssistantDuplicateText = nil
            state.goalActionError = nil
            (state.lastTurnError, state.failedSessionHandoffMessage) = (nil, nil)
            try await agentsManager.startGoal(objective, conversationId: conversation.id)
            state.respawnAttempts = 0
        }
    }
}
