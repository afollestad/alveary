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

    func flushPendingSaveIfNeeded() async {
        // A finishing save can schedule a follow-up snapshot; approval resumes need the final cursor.
        while let saveTask {
            await saveTask.value
        }
    }
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
