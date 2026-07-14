import Foundation

extension ConversationViewModel {
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
        thread.hasCompletedInitialSetup = false
    }

    func finishFailedInitialSetupRollback(project: Project?, thread: AgentThread) async {
        guard thread.effectiveMode == .project,
              thread.useWorktree,
              let project,
              let path = thread.worktreePath else {
            persistRollbackMetadataReset()
            return
        }

        do {
            try await worktreeManager.remove(
                projectPath: project.path,
                worktreePath: path,
                branch: thread.branch
            )
            thread.worktreePath = nil
            thread.branch = nil
            try modelContext.save()
        } catch let cleanupError {
            preserveWorktreeAfterFailedRollback(cleanupError: cleanupError, thread: thread)
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
