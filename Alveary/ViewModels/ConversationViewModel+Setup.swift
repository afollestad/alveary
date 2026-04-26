import Foundation
import SwiftData

private struct ConversationInitialSetupSnapshot {
    let draft: String
    let stagedContext: String?
}

// Cancellation deletes the attempted bubble, so restore any auto-naming side effects.
private struct LocalUserMessageAttemptMetadata {
    let conversationTitle: String?
    let threadName: String?
    let threadHasCustomName: Bool?
}

private struct LocalUserMessageAttempt {
    let id: String
    let stagedContext: String?
    let insertedMessage: Bool
    let metadata: LocalUserMessageAttemptMetadata?
}

extension ConversationViewModel {
    func dbConversation() -> Conversation? {
        modelContext.resolveConversation(id: conversationModelID)
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

    private func prepareLocalUserMessageAttempt(
        message: String,
        stagedContextOverride: String?
    ) throws -> LocalUserMessageAttempt {
        let appliedContext = stagedContextOverride ?? state.stagedContext
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        let metadata = LocalUserMessageAttemptMetadata(
            conversationTitle: dbConversation.title,
            threadName: dbConversation.thread?.name,
            threadHasCustomName: dbConversation.thread?.hasCustomName
        )
        let localUserMessageID = insertLocalUserMessage(
            message,
            into: dbConversation,
            shouldAutoNameThread: true
        ).id

        if stagedContextOverride == nil {
            state.stagedContext = nil
        }

        return LocalUserMessageAttempt(
            id: localUserMessageID,
            stagedContext: appliedContext,
            insertedMessage: true,
            metadata: metadata
        )
    }

    private func localUserMessageAttempt(
        message: String,
        stagedContextOverride: String?,
        existingLocalUserMessageID: String?
    ) throws -> LocalUserMessageAttempt {
        if let existingLocalUserMessageID {
            return LocalUserMessageAttempt(
                id: existingLocalUserMessageID,
                stagedContext: stagedContextOverride ?? state.stagedContext,
                insertedMessage: false,
                metadata: nil
            )
        }

        return try prepareLocalUserMessageAttempt(
            message: message,
            stagedContextOverride: stagedContextOverride
        )
    }

    private func markLocalUserMessageAttemptFailedIfNeeded(
        _ attempt: LocalUserMessageAttempt,
        error: Error
    ) {
        guard attempt.insertedMessage else {
            return
        }

        state.markRetryableFailedMessage(id: attempt.id, stagedContext: attempt.stagedContext)
        if state.lastTurnError == nil {
            state.lastTurnError = error.localizedDescription
        }
        scheduleSave()
    }

    private func removeLocalUserMessageAttempt(
        id: String,
        restoring metadata: LocalUserMessageAttemptMetadata?
    ) {
        if let record = try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first {
            modelContext.delete(record)
        }

        if let dbConversation = dbConversation() {
            dbConversation.title = metadata?.conversationTitle
            if let thread = dbConversation.thread {
                if let threadName = metadata?.threadName {
                    thread.name = threadName
                }
                if let threadHasCustomName = metadata?.threadHasCustomName {
                    thread.hasCustomName = threadHasCustomName
                }
            }
        }

        state.clearRetryableFailedMessage(id: id)
        rebuildChatItemsIfNeeded(from: conversationEventRecords(), forceFullRebuild: true)

        do {
            try modelContext.save()
        } catch {
            state.lastTurnError = "Failed to remove cancelled message attempt: \(error.localizedDescription)"
        }
    }

    private func conversationEventRecords() -> [ConversationEventRecord] {
        let conversationID = conversation.id
        return (try? modelContext.fetch(
            FetchDescriptor<ConversationEventRecord>(
                predicate: #Predicate { $0.conversationId == conversationID },
                sortBy: [
                    SortDescriptor(\.timestamp),
                    SortDescriptor(\.id)
                ]
            )
        )) ?? []
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

        let permissionModeOverride: String?
        if state.pendingToolApproval?.request.toolName == "ExitPlanMode" {
            permissionModeOverride = "plan"
        } else {
            permissionModeOverride = state.runtimePermissionMode
        }

        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: permissionModeOverride ?? dbConversation.thread?.permissionMode,
            model: dbConversation.thread?.model,
            effort: AppSettings.normalizedEffortLevel(dbConversation.thread?.effort),
            initialPrompt: initialPrompt
        )
    }

    func prepareForSpawn(config: AgentSpawnConfig) async {
        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: settingsService.current.autoTrustProjects
        )
    }

    func withOutboundReservation<T>(_ body: () async throws -> T) async throws -> T {
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied")
        }
        guard !hasUnansweredPrompt else {
            throw AgentError.spawnFailed("Answer the pending question before sending another message")
        }
        guard state.pendingToolApproval == nil else {
            throw AgentError.spawnFailed("Approve or deny the pending tool use before sending another message")
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
        let attempt = try localUserMessageAttempt(
            message: message,
            stagedContextOverride: stagedContextOverride,
            existingLocalUserMessageID: existingLocalUserMessageID
        )

        do {
            if needsSetup {
                try await setupAndStartReserved(
                    message,
                    stagedContextOverride: stagedContextOverride,
                    existingLocalUserMessageID: attempt.id,
                    snapshotStagedContext: attempt.stagedContext
                )
                return
            }

            if await needsRespawn() {
                try await startAgentReserved(config: makeSpawnConfig())
                state.respawnAttempts = 0
            }

            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride ?? (attempt.insertedMessage ? attempt.stagedContext : nil),
                existingLocalUserMessageID: attempt.id
            )
        } catch is CancellationError {
            if attempt.insertedMessage {
                removeLocalUserMessageAttempt(
                    id: attempt.id,
                    restoring: attempt.metadata
                )
            }
            throw CancellationError()
        } catch {
            markLocalUserMessageAttemptFailedIfNeeded(attempt, error: error)
            throw error
        }
    }

    private func setupAndStartReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        existingLocalUserMessageID: String? = nil,
        snapshotStagedContext: String? = nil
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
            stagedContext: snapshotStagedContext ?? state.stagedContext
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
                stagedContextOverride: stagedContextOverride ?? snapshotStagedContext,
                existingLocalUserMessageID: existingLocalUserMessageID
            )
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
        snapshot: ConversationInitialSetupSnapshot,
        restoresDraft: Bool
    ) async throws {
        cancelPendingRuntimeTasks()
        try await destroyRuntimeAfterFailedInitialSetup(originalError: error)
        restoreStateAfterFailedInitialSetup(
            snapshot: snapshot,
            thread: thread,
            restoresDraft: restoresDraft
        )
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
        thread: AgentThread,
        restoresDraft: Bool
    ) {
        if restoresDraft {
            replaceState(with: runtimeStore.conversationState(for: conversation.id))
            state.inputDraft = snapshot.draft
            state.stagedContext = snapshot.stagedContext
        }
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
