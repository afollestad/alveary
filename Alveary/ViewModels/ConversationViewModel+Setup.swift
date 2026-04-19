import Foundation
import SwiftData

private struct ConversationInitialSetupSnapshot {
    let draft: String
    let stagedContext: String?
}

extension ConversationViewModel {
    func dbConversation() -> Conversation? {
        modelContext.model(for: conversationModelID) as? Conversation
    }

    func dbThread() -> AgentThread? {
        dbConversation()?.thread
    }

    func needsRespawn() async -> Bool {
        guard !needsSetup else {
            return false
        }
        return !(await agentsManager.isRunning(conversationId: conversation.id))
    }

    func repairMissingWorktreeIfNeeded() throws {
        guard let thread = dbThread(),
              thread.useWorktree,
              thread.hasCompletedInitialSetup,
              let worktreePath = thread.worktreePath,
              !FileManager.default.fileExists(atPath: worktreePath) else {
            return
        }

        if let branch = thread.branch,
           !thread.pendingCleanupBranches.contains(branch) {
            thread.pendingCleanupBranches.append(branch)
        }
        thread.branch = nil
        thread.worktreePath = nil
        thread.hasCompletedInitialSetup = false
        try modelContext.save()
    }

    func makeSpawnConfig(
        workingDirectory overrideWorkingDirectory: String? = nil,
        initialPrompt: String? = nil
    ) throws -> AgentSpawnConfig {
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        let providerId = dbConversation.provider ?? settingsService.current.defaultProvider
        let workingDirectory = overrideWorkingDirectory
            ?? dbConversation.thread?.worktreePath
            ?? dbConversation.thread?.project?.path

        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AgentError.spawnFailed("Cannot spawn agent: no working directory")
        }

        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: dbConversation.thread?.permissionMode,
            model: dbConversation.thread?.model,
            effort: AppSettings.normalizedEffortLevel(dbConversation.thread?.effort),
            initialPrompt: initialPrompt
        )
    }

    func prepareForSpawn(config: AgentSpawnConfig) async {
        let shouldAutoTrust = settingsService.current.autoTrustWorktrees && (dbThread()?.useWorktree ?? false)
        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: shouldAutoTrust
        )
    }

    func withOutboundReservation<T>(_ body: () async throws -> T) async throws -> T {
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied")
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Another message is already being sent")
        }

        state.isSendingMessage = true
        defer { state.isSendingMessage = false }
        return try await body()
    }

    func startAgentReserved(config: AgentSpawnConfig) async throws {
        await prepareForSpawn(config: config)
        try await agentsManager.spawn(id: conversation.id, config: config)
        subscribe()
    }

    func deliverMessageReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        existingLocalUserMessageID: String? = nil
    ) async throws {
        try repairMissingWorktreeIfNeeded()

        if needsSetup {
            try await setupAndStartReserved(
                message,
                stagedContextOverride: stagedContextOverride,
                existingLocalUserMessageID: existingLocalUserMessageID
            )
            return
        }

        if await needsRespawn() {
            try await startAgentReserved(config: makeSpawnConfig())
            state.respawnAttempts = 0
        }

        try await sendReserved(
            message,
            stagedContextOverride: stagedContextOverride,
            existingLocalUserMessageID: existingLocalUserMessageID
        )
    }

    func setupAndStartReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        existingLocalUserMessageID: String? = nil
    ) async throws {
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil

        guard let dbConversation = dbConversation(),
              let thread = dbConversation.thread,
              let project = thread.project else {
            throw AgentError.spawnFailed("No project associated with this thread")
        }

        let snapshot = ConversationInitialSetupSnapshot(
            draft: message,
            stagedContext: state.stagedContext
        )

        do {
            let workingDirectory = try await createInitialWorkingDirectory(
                for: thread,
                project: project,
                message: message
            )
            setupPhase = .startingAgent
            try await startAgentReserved(config: makeSpawnConfig(workingDirectory: workingDirectory))
            thread.hasCompletedInitialSetup = true
            try modelContext.save()
            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride,
                existingLocalUserMessageID: existingLocalUserMessageID
            )
        } catch {
            try await rollbackFailedInitialSetup(
                error: error,
                project: project,
                thread: thread,
                snapshot: snapshot
            )
            throw error
        }

        setupPhase = nil
    }

    private func createInitialWorkingDirectory(
        for thread: AgentThread,
        project: Project,
        message: String
    ) async throws -> String {
        guard thread.useWorktree else {
            return project.path
        }

        guard project.isGitRepository else {
            thread.useWorktree = false
            try modelContext.save()
            return project.path
        }

        setupPhase = .creatingWorktree
        let worktreeSlug = Self.threadName(from: message) ?? thread.name

        do {
            let info = try await worktreeManager.create(
                projectPath: project.path,
                threadName: worktreeSlug,
                baseRef: project.baseRef,
                remoteName: project.remoteName
            )
            thread.worktreePath = info.path
            thread.branch = info.branch
            try modelContext.save()
            return info.path
        } catch {
            await rollbackFailedWorktreeCreation(for: thread, project: project)
            setupPhase = nil
            throw error
        }
    }

    private func rollbackFailedInitialSetup(
        error: Error,
        project: Project,
        thread: AgentThread,
        snapshot: ConversationInitialSetupSnapshot
    ) async throws {
        cancelPendingRuntimeTasks()
        try await destroyRuntimeAfterFailedInitialSetup(originalError: error)
        restoreStateAfterFailedInitialSetup(snapshot: snapshot, thread: thread)
        await finishFailedInitialSetupRollback(project: project, thread: thread)
        setupPhase = nil
    }
}

private extension ConversationViewModel {
    func rollbackFailedWorktreeCreation(for thread: AgentThread, project: Project) async {
        guard let path = thread.worktreePath else {
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
        } catch {
            state.lastTurnError =
                "Initial worktree setup failed and rollback cleanup/metadata clear also failed: " +
                error.localizedDescription
        }
    }

    func cancelPendingRuntimeTasks() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        saveTask?.cancel()
        saveTask = nil
        saveTaskID = nil
        needsFollowUpSave = false
    }

    func destroyRuntimeAfterFailedInitialSetup(originalError: Error) async throws {
        do {
            try await agentsManager.destroyRuntime(conversationId: conversation.id)
        } catch let cleanupError {
            state.lastTurnError =
                "Initial setup failed: \(originalError.localizedDescription). Runtime cleanup also failed: " +
                cleanupError.localizedDescription
            setupPhase = nil
            throw AgentError.spawnFailed(state.lastTurnError ?? cleanupError.localizedDescription)
        }
    }

    func restoreStateAfterFailedInitialSetup(
        snapshot: ConversationInitialSetupSnapshot,
        thread: AgentThread
    ) {
        replaceState(with: runtimeStore.conversationState(for: conversation.id))
        state.inputDraft = snapshot.draft
        state.stagedContext = snapshot.stagedContext
        thread.hasCompletedInitialSetup = false
    }

    func finishFailedInitialSetupRollback(project: Project, thread: AgentThread) async {
        guard thread.useWorktree, let path = thread.worktreePath else {
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
