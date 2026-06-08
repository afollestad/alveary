import AgentCLIKit
import Foundation
import SwiftData

private struct ConversationInitialSetupSnapshot {
    let draft: String
    let draftSource: ComposerDraftSource
    let stagedContext: String?
}

// Cancellation deletes the attempted bubble, so restore local secondary-title side effects.
private struct LocalUserMessageAttemptMetadata {
    let restoresConversationTitle: Bool
    let conversationTitle: String?
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
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool
    ) throws -> LocalUserMessageAttempt {
        let appliedContext = stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil)
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        let restoresConversationTitle = !dbConversation.isMain
        let metadata = LocalUserMessageAttemptMetadata(
            restoresConversationTitle: restoresConversationTitle,
            conversationTitle: restoresConversationTitle ? dbConversation.title : nil
        )
        let localUserMessageID = insertLocalUserMessage(
            message,
            into: dbConversation
        ).id

        if useCurrentStagedContextWhenOverrideNil && stagedContextOverride == nil {
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
        useCurrentStagedContextWhenOverrideNil: Bool,
        existingLocalUserMessageID: String?
    ) throws -> LocalUserMessageAttempt {
        if let existingLocalUserMessageID {
            return LocalUserMessageAttempt(
                id: existingLocalUserMessageID,
                stagedContext: stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil),
                insertedMessage: false,
                metadata: nil
            )
        }

        return try prepareLocalUserMessageAttempt(
            message: message,
            stagedContextOverride: stagedContextOverride,
            useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil
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

        if let dbConversation = dbConversation(), metadata?.restoresConversationTitle == true {
            dbConversation.title = metadata?.conversationTitle
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

    func prepareForSpawn(config: AgentSpawnConfig) async {
        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: settingsService.current.autoTrustProjects
        )
    }

    func startAgentReserved(config: AgentSpawnConfig) async throws {
        await prepareForSpawn(config: config)
        try await agentsManager.spawn(id: conversation.id, config: config)
        state.liveSessionConfig = config
        subscribe()
    }

    func deliverMessageReserved(
        _ message: String,
        stagedContextOverride: String? = nil,
        useCurrentStagedContextWhenOverrideNil: Bool = true,
        existingLocalUserMessageID: String? = nil,
        respawnSettingsSource: SessionSettingsConfigSource = .nextTurn
    ) async throws {
        try repairMissingWorktreeIfNeeded()
        let attempt = try localUserMessageAttempt(
            message: message,
            stagedContextOverride: stagedContextOverride,
            useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
            existingLocalUserMessageID: existingLocalUserMessageID
        )

        do {
            if needsSetup {
                try await setupAndStartReserved(
                    message,
                    stagedContextOverride: stagedContextOverride,
                    useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
                    existingLocalUserMessageID: attempt.id,
                    snapshotStagedContext: attempt.stagedContext
                )
                return
            }

            if await needsRespawn() {
                try await startAgentReserved(config: makeSpawnConfig(
                    settingsSource: respawnSettingsSource
                ))
                state.respawnAttempts = 0
            }

            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride ?? (attempt.insertedMessage ? attempt.stagedContext : nil),
                useCurrentStagedContextWhenOverrideNil: false,
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
        useCurrentStagedContextWhenOverrideNil: Bool = true,
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
            draftSource: state.inputDraftSource,
            stagedContext: snapshotStagedContext ?? state.stagedContext
        )

        do {
            let workingDirectory = try await createInitialWorkingDirectory(
                for: thread,
                project: project,
                message: message
            )
            setupPhase = .startingAgent
            try await startAgentReserved(config: makeSpawnConfig(workingDirectory: workingDirectory, settingsSource: .nextTurn))
            thread.hasCompletedInitialSetup = true
            try modelContext.save()
            try await sendReserved(
                message,
                stagedContextOverride: stagedContextOverride ?? snapshotStagedContext,
                useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
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
        let worktreeSlug = AgentSessionPreviewGenerator.preview(fromInitialPrompt: message) ?? thread.name

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
            replaceInputDraft(snapshot.draft, source: snapshot.draftSource)
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
