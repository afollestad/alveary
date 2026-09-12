import Foundation

extension ConversationViewModel {
    func rollbackFailedInitialSetup(
        error: Error,
        project: Project?,
        thread: AgentThread,
        snapshot: ConversationInitialSetupSnapshot,
        restoresDraft: Bool
    ) async throws {
        cancelPendingRuntimeTasks()
        let threadID = thread.persistentModelID
        try await destroyRuntimeAfterFailedInitialSetup(originalError: error)
        guard let thread = modelContext.resolveThread(id: threadID) else { setupPhase = nil; return }
        restoreStateAfterFailedInitialSetup(
            snapshot: snapshot,
            thread: thread,
            restoresDraft: restoresDraft
        )
        await finishFailedInitialSetupRollback(project: project, thread: thread)
        setupPhase = nil
    }

    func cancelPendingRuntimeTasks() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
        needsFollowUpSave = false
    }

    func destroyRuntimeIgnoringTaskCancellation() async throws {
        let agentsManager = agentsManager
        let conversationID = conversation.id
        let cleanup = Task {
            try await agentsManager.destroyRuntimePreservingState(conversationId: conversationID)
        }
        try await cleanup.value
    }

    func destroyRuntimeAfterFailedInitialSetup(originalError: Error) async throws {
        // Initial-setup cancellation reaches this path from an already-cancelled task. Destructive
        // teardown must run in its own uncancelled task so provider cleanup can finish and be joined.
        do {
            try await destroyRuntimeIgnoringTaskCancellation()
        } catch let cleanupError {
            runtimeStore.bindConversationState(state, for: conversation.id)
            state.lastTurnError =
                "Initial setup failed: \(originalError.localizedDescription). Runtime cleanup also failed: " +
                cleanupError.localizedDescription
            setupPhase = nil
            throw AgentError.spawnFailed(state.lastTurnError ?? cleanupError.localizedDescription)
        }
    }

    func restoreStateAfterFailedInitialSetup(
        snapshot: ConversationInitialSetupSnapshot,
        thread: AgentThread,
        restoresDraft: Bool
    ) {
        if restoresDraft {
            let appShotsStagedDuringSetup = state.stagedAppShots
            let replacementState = ConversationState()
            replacementState.isAutomatedScheduledRunActive = state.isAutomatedScheduledRunActive
            replaceState(with: replacementState)
            replaceInputDraft(snapshot.draft, source: snapshot.draftSource)
            state.stagedContext = snapshot.stagedContext
            state.stagedImageAttachments = snapshot.stagedImageAttachments
            state.stagedFileAttachments = snapshot.stagedFileAttachments
            let restoredAppShotIDs = Set(snapshot.stagedAppShots.map(\.id))
            state.stagedAppShots = snapshot.stagedAppShots + appShotsStagedDuringSetup.filter {
                !restoredAppShotIDs.contains($0.id)
            }
            refreshInputDraftEffectiveEmptyForAttachments()
        } else {
            // Keep the mounted/retry state canonical for root-routed staging after teardown.
            runtimeStore.bindConversationState(state, for: conversation.id)
            if !snapshot.stagedFileAttachments.isEmpty {
                state.stagedFileAttachments = snapshot.stagedFileAttachments
                refreshInputDraftEffectiveEmptyForAttachments()
            }
        }
        // The runtime arms a turn when it installs the spawn's event buffer, before the provider
        // process starts. A failed spawn emits no terminal event, so nothing else ever ends that
        // turn: the composer would stay busy forever, which also gates off the pre-startup
        // provider switch. Runs after both branches so a late arm on a replacement state is
        // covered too.
        state.rollBackOptimisticTurn()
        state.clearStreamingText()
        state.activeRuntimeActivityTurnId = nil
        thread.hasCompletedInitialSetup = false
    }

    func finishFailedInitialSetupRollback(project _: Project?, thread: AgentThread) async {
        guard thread.effectiveMode == .project,
              thread.useWorktree,
              let source = thread.sourceFolder,
              let path = thread.worktreePath else {
            persistRollbackMetadataReset()
            return
        }

        let threadID = thread.persistentModelID
        let branch = thread.branch
        do {
            let manager = worktreeManager
            let cleanup = Task { try await manager.remove(projectPath: source.path, worktreePath: path, branch: branch) }
            try await cleanup.value
            if let liveThread = modelContext.resolveThread(id: threadID), liveThread.worktreePath == path {
                liveThread.worktreePath = nil
                liveThread.branch = nil
                try modelContext.save()
            }
        } catch let cleanupError {
            if let liveThread = modelContext.resolveThread(id: threadID), liveThread.worktreePath == path {
                preserveWorktreeAfterFailedRollback(cleanupError: cleanupError, thread: liveThread)
            }
        }
    }

    func persistRollbackMetadataReset() {
        do {
            try modelContext.save()
        } catch {
            state.lastTurnError = "Initial spawn failed and rollback metadata reset also failed: \(error.localizedDescription)"
        }
    }

    func preserveWorktreeAfterFailedRollback(cleanupError: Error, thread: AgentThread) {
        thread.hasCompletedInitialSetup = true

        do {
            try modelContext.save()
            state.lastTurnError =
                "Initial setup failed and rollback worktree cleanup also failed: " +
                "\(cleanupError.localizedDescription). The existing worktree was preserved, " +
                "so retry will reuse it instead of creating a second worktree."
        } catch {
            state.lastTurnError =
                "Initial setup failed, rollback cleanup failed, and preserved thread metadata " +
                "could not be saved: \(error.localizedDescription)"
        }
    }
}
