import Foundation

extension ConversationViewModel {
    func scheduleSave() {
        guard saveTask == nil else {
            needsFollowUpSave = true
            return
        }

        let snapshot = ConversationSaveSnapshot(
            observedIndex: state.lastObservedEventIndex,
            generation: state.activeBufferGeneration,
            taskID: UUID(),
            delay: .milliseconds(state.turnState.isActive ? 350 : 150)
        )
        saveTaskID = snapshot.taskID
        saveTask = Task { @MainActor [snapshot] in
            await performScheduledSave(snapshot)
        }
    }

    /// Mirrors a controller turn's outcome onto the conversation so a failure outlives the app
    /// session. Hidden turns are excluded — a failed commit-message generation must not paint the
    /// thread red — and `wasVisible` is captured when the turn ended, so a later
    /// `recordLocalVisibleTurnEndedIfNeeded()` cannot retroactively hide it.
    func recordDurableTurnOutcome(_ boundary: ConversationTerminalBoundary) {
        guard boundary.wasVisible else {
            return
        }
        if case .failed = boundary.result {
            applyDurableTurnFailure(Date())
        } else {
            applyDurableTurnFailure(nil)
        }
    }

    /// Drops a recorded failure when a new attempt begins. `ThreadStatus.folded` leans on this:
    /// a surviving flag is what proves a `.busy` signal belongs to a turn that never ended.
    ///
    /// Two callers, and the order matters. `markVisibleTurnStarted()` is the general owner, but
    /// `sendReserved` clears again *before* dispatching, because the dispatch is what puts the
    /// runtime in `.busy` and `markVisibleTurnStarted()` only runs once it returns — clearing
    /// solely there can paint the row red for the frames in between. It sits with the
    /// `lastTurnError` reset for the same reason: a new attempt drops the previous turn's fallout.
    func clearDurableTurnFailure() {
        applyDurableTurnFailure(nil)
    }

    /// Writes the flag and deliberately schedules no save of its own.
    ///
    /// This runs inside `recordControllerTerminalBoundary()`, and `scheduleSave()` mutates
    /// `saveTask`, which `hasPendingPersistence` exposes to the controller registry's observation.
    /// Scheduling from here re-enters the registry on the very boundary it is reconciling, and its
    /// terminal flush then waits on a save that keeps rescheduling — the suite livelocks on the
    /// terminal-save paths. The sidebar reads the property, not the file, and every caller that
    /// records a boundary either schedules its own save or is followed by the registry's terminal
    /// flush, which saves the context outright.
    private func applyDurableTurnFailure(_ failedAt: Date?) {
        guard let dbConversation = dbConversation(),
              (dbConversation.lastTurnFailedAt != nil) != (failedAt != nil) else {
            return
        }
        dbConversation.lastTurnFailedAt = failedAt
    }

    func flushPendingSaveIfNeeded() async {
        // A finishing save can schedule a follow-up snapshot; approval resumes need the final cursor.
        while let saveTask {
            await saveTask.value
        }
    }

    func flushPendingSaveNow() async throws {
        let acknowledgement = try flushPendingSaveSynchronously()
        guard let acknowledgement else {
            return
        }
        await agentsManager.markPersisted(
            conversationId: conversation.id,
            generation: acknowledgement.generation,
            upTo: acknowledgement.index
        )
    }

    @discardableResult
    func flushPendingSaveSynchronously() throws -> ConversationPersistenceAcknowledgement? {
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
        needsFollowUpSave = false

        try modelContext.save()

        state.lastPersistedEventIndex = max(state.lastPersistedEventIndex, state.lastObservedEventIndex)
        guard let generation = state.activeBufferGeneration else {
            return nil
        }
        return ConversationPersistenceAcknowledgement(
            generation: generation,
            index: state.lastPersistedEventIndex
        )
    }
}

struct ConversationPersistenceAcknowledgement: Equatable, Sendable {
    let generation: UUID
    let index: Int
}

// Save snapshots decouple debounced model saves from runtime-buffer acknowledgement.
// If saving fails, the persisted cursor stays behind so reconnects replay unsaved events.
private struct ConversationSaveSnapshot {
    let observedIndex: Int
    let generation: UUID?
    let taskID: UUID
    let delay: Duration
}

private extension ConversationViewModel {
    func performScheduledSave(_ snapshot: ConversationSaveSnapshot) async {
        guard await waitForScheduledSave(snapshot) else {
            return
        }

        await persistScheduledSave(snapshot)
        finishScheduledSave(taskID: snapshot.taskID)
    }

    func waitForScheduledSave(_ snapshot: ConversationSaveSnapshot) async -> Bool {
        do {
            try await Task.sleep(for: snapshot.delay)
            try Task.checkCancellation()
            return true
        } catch {
            finishScheduledSave(taskID: snapshot.taskID)
            return false
        }
    }

    func persistScheduledSave(_ snapshot: ConversationSaveSnapshot) async {
        do {
            try modelContext.save()
        } catch {
            return
        }

        guard state.activeBufferGeneration == snapshot.generation, !Task.isCancelled else {
            return
        }
        state.lastPersistedEventIndex = max(state.lastPersistedEventIndex, snapshot.observedIndex)
        if let generation = snapshot.generation {
            await agentsManager.markPersisted(
                conversationId: conversation.id,
                generation: generation,
                upTo: snapshot.observedIndex
            )
        }
    }

    func finishScheduledSave(taskID: UUID) {
        guard saveTaskID == taskID else {
            return
        }

        (saveTask, saveTaskID) = (nil, nil)
        guard needsFollowUpSave else {
            return
        }

        needsFollowUpSave = false
        scheduleSave()
    }
}
