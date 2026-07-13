import Foundation

extension ConversationViewModel {
    func setupHiddenInitialRuntimeIfNeeded() async throws {
        try materializeDraftWithoutMessageIfNeeded()
        guard needsSetup else {
            return
        }

        try await setupHiddenInitialRuntime()
    }
}

private extension ConversationViewModel {
    func setupHiddenInitialRuntime() async throws {
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil

        guard let dbConversation = dbConversation(),
              let thread = dbConversation.thread else {
            throw AgentError.spawnFailed("No thread associated with this conversation")
        }
        let project = thread.project

        let snapshot = ConversationInitialSetupSnapshot(
            draft: state.inputDraft,
            draftSource: state.inputDraftSource,
            stagedContext: state.stagedContext,
            stagedImageAttachments: state.stagedImageAttachments,
            stagedFileAttachments: state.stagedFileAttachments,
            stagedAppShots: state.stagedAppShots
        )

        do {
            // Keep large generated diff prompts out of worktree branch naming.
            let workingDirectory = try await createInitialWorkingDirectory(
                for: thread,
                project: project,
                message: thread.name
            )
            setupPhase = .startingAgent
            try await startAgentReserved(config: makeSpawnConfig(
                workingDirectory: workingDirectory,
                settingsSource: .nextTurn
            ))
            try completeHiddenInitialSetup(thread: thread)
        } catch {
            try await rollbackFailedInitialSetup(
                error: error,
                project: project,
                thread: thread,
                snapshot: snapshot,
                restoresDraft: error is CancellationError
            )
            throw error
        }

        setupPhase = nil
    }

    func completeHiddenInitialSetup(thread: AgentThread) throws {
        thread.hasCompletedInitialSetup = true
        try modelContext.save()
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.activeRuntimeActivityTurnId = nil
        state.respawnAttempts = 0
    }
}
