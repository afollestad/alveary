import AgentCLIKit
import Foundation
import SwiftData

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
        outbound: OutboundMessageText,
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
            outbound.visibleText,
            into: dbConversation
        ).id

        if useCurrentStagedContextWhenOverrideNil && stagedContextOverride == nil {
            state.stagedContext = nil
        }

        return LocalUserMessageAttempt(
            id: localUserMessageID,
            stagedContext: appliedContext,
            transportText: outbound.transportText,
            attachments: outbound.attachments,
            appShots: outbound.appShots,
            providerMetadata: outbound.providerMetadata,
            consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
            insertedMessage: true,
            metadata: metadata
        )
    }

    private func localUserMessageAttempt(
        outbound: OutboundMessageText,
        stagedContextOverride: String?,
        useCurrentStagedContextWhenOverrideNil: Bool,
        existingLocalUserMessageID: String?
    ) throws -> LocalUserMessageAttempt {
        if let existingLocalUserMessageID {
            return LocalUserMessageAttempt(
                id: existingLocalUserMessageID,
                stagedContext: stagedContextOverride ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil),
                transportText: outbound.transportText,
                attachments: outbound.attachments,
                appShots: outbound.appShots,
                providerMetadata: outbound.providerMetadata,
                consumedExitPlanModeRevisionGuidance: outbound.consumedExitPlanModeRevisionGuidance,
                insertedMessage: false,
                metadata: nil
            )
        }

        return try prepareLocalUserMessageAttempt(
            outbound: outbound,
            stagedContextOverride: stagedContextOverride,
            useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil
        )
    }

    private func markLocalUserMessageAttemptFailedIfNeeded(
        _ attempt: LocalUserMessageAttempt,
        error: Error,
        stagedContextOverride: String? = nil
    ) {
        guard attempt.insertedMessage else {
            return
        }

        state.markRetryableFailedMessage(
            id: attempt.id,
            stagedContext: stagedContextOverride ?? attempt.stagedContext,
            transportText: attempt.transportText,
            attachments: attempt.attachments,
            appShots: attempt.appShots,
            providerMetadata: attempt.providerMetadata
        )
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
        state.runtimeSpeedMode = config.speedMode
        subscribe()
    }

    // swiftlint:disable:next function_body_length
    func deliverMessageReserved(
        _ message: String,
        transportTextOverride: String? = nil,
        initialGoal: String? = nil,
        attachments: [LocalImageAttachment] = [],
        appShots: [AppShotAttachment] = [],
        providerMetadata: [String: AgentCLIKit.JSONValue] = [:],
        consumedAttachments: [LocalImageAttachment] = [],
        consumedAppShots: [AppShotAttachment] = [],
        consumedExitPlanModeRevisionGuidance: PendingExitPlanModeRevisionGuidance? = nil,
        stagedContextOverride: String? = nil,
        useCurrentStagedContextWhenOverrideNil: Bool = true,
        existingLocalUserMessageID: String? = nil,
        respawnSettingsSource: SessionSettingsConfigSource = .nextTurn,
        marksSessionHandoffSeedTurn: Bool = false,
        failureHandling: LocalUserMessageFailureHandling = .retryable
    ) async throws {
        try repairMissingWorktreeIfNeeded()
        let resolvedStagedContext = try await prepareRuntimeAndResolveSessionRecoveryContext(
            stagedContextOverride: stagedContextOverride,
            useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
            respawnSettingsSource: respawnSettingsSource
        )
        if resolvedStagedContext.consumedCurrentStagedContext != nil { state.stagedContext = nil }
        let attempt = try localUserMessageAttempt(
            outbound: OutboundMessageText(
                visibleText: message,
                transportText: transportTextOverride,
                attachments: attachments,
                appShots: appShots,
                providerMetadata: providerMetadata,
                consumedAttachments: consumedAttachments,
                consumedAppShots: consumedAppShots,
                consumedExitPlanModeRevisionGuidance: consumedExitPlanModeRevisionGuidance
            ),
            stagedContextOverride: resolvedStagedContext.stagedContext,
            useCurrentStagedContextWhenOverrideNil: resolvedStagedContext.recoveryContext == nil ? useCurrentStagedContextWhenOverrideNil : false,
            existingLocalUserMessageID: existingLocalUserMessageID
        )
        var retryStagedContext = attempt.stagedContext
        clearStagedImageAttachmentsIfTheyMatch(consumedAttachments)
        clearStagedAppShotsIfTheyMatch(consumedAppShots)

        do {
            if needsSetup {
                try await setupAndStartReserved(
                    message,
                    transportText: transportTextOverride,
                    attachments: attachments,
                    appShots: appShots,
                    initialGoal: initialGoal,
                    providerMetadata: providerMetadata,
                    stagedContextOverride: stagedContextOverride,
                    useCurrentStagedContextWhenOverrideNil: useCurrentStagedContextWhenOverrideNil,
                    existingLocalUserMessageID: attempt.id,
                    snapshotStagedContext: attempt.stagedContext
                )
                state.markTranscriptImageAttachments(id: attempt.id, attachments: attempt.attachments)
                state.markTranscriptAppShots(id: attempt.id, appShots: attempt.appShots)
                return
            }

            try await sendAttemptWithSingleRespawnRecovery(
                OutboundMessageText(
                    visibleText: message,
                    transportText: transportTextOverride,
                    attachments: attachments,
                    appShots: appShots,
                    providerMetadata: providerMetadata
                ),
                stagedContextOverride: resolvedStagedContext.stagedContext ?? (attempt.insertedMessage ? attempt.stagedContext : nil),
                useCurrentStagedContextWhenOverrideNil: false,
                existingLocalUserMessageID: attempt.id,
                respawnSettingsSource: respawnSettingsSource,
                marksSessionHandoffSeedTurn: marksSessionHandoffSeedTurn,
                initialGoal: initialGoal,
                onResolvedRecoveryContext: { retryStagedContext = $0.stagedContext }
            )
            clearConsumedPendingRestoreContext(resolvedStagedContext)
            state.markTranscriptImageAttachments(id: attempt.id, attachments: attempt.attachments)
            state.markTranscriptAppShots(id: attempt.id, appShots: attempt.appShots)
        } catch is CancellationError {
            cancelLocalUserMessageAttemptIfNeeded(attempt)
            throw CancellationError()
        } catch {
            handleLocalUserMessageAttemptFailure(
                error,
                attempt: attempt,
                retryStagedContext: retryStagedContext,
                failureHandling: failureHandling
            )
            throw error
        }
    }

    private func handleLocalUserMessageAttemptFailure(
        _ error: Error,
        attempt: LocalUserMessageAttempt,
        retryStagedContext: String?,
        failureHandling: LocalUserMessageFailureHandling
    ) {
        switch failureHandling {
        case .retryable:
            markLocalUserMessageAttemptFailedIfNeeded(attempt, error: error, stagedContextOverride: retryStagedContext)
        case .removeAttempt:
            removeLocalUserMessageAttempt(id: attempt.id, restoring: attempt.metadata)
            if state.stagedContext == nil {
                state.stagedContext = retryStagedContext
            }
            restoreExitPlanModeRevisionGuidanceIfNeeded(attempt.consumedExitPlanModeRevisionGuidance)
            if state.lastTurnError == nil {
                state.lastTurnError = error.localizedDescription
            }
        }
    }

    private func cancelLocalUserMessageAttemptIfNeeded(_ attempt: LocalUserMessageAttempt) {
        guard attempt.insertedMessage else { return }
        removeLocalUserMessageAttempt(id: attempt.id, restoring: attempt.metadata)
        restoreExitPlanModeRevisionGuidanceIfNeeded(attempt.consumedExitPlanModeRevisionGuidance)
    }

    private func setupAndStartReserved(
        _ message: String,
        transportText: String?,
        attachments: [LocalImageAttachment],
        appShots: [AppShotAttachment],
        initialGoal: String? = nil,
        providerMetadata: [String: AgentCLIKit.JSONValue],
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

        let resolvedStagedContext = snapshotStagedContext ?? (useCurrentStagedContextWhenOverrideNil ? state.stagedContext : nil)
        let snapshot = ConversationInitialSetupSnapshot(
            draft: message,
            draftSource: state.inputDraftSource,
            stagedContext: resolvedStagedContext,
            stagedImageAttachments: attachments,
            stagedAppShots: appShots
        )

        do {
            let workingDirectory = try await createInitialWorkingDirectory(
                for: thread,
                project: project,
                message: message
            )
            let transportMessage = buildTransportMessage(
                message: transportText ?? message,
                stagedContext: snapshot.stagedContext
            )
            setupPhase = .startingAgent
            try await startAgentReserved(config: makeSpawnConfig(
                workingDirectory: workingDirectory,
                initialPrompt: transportMessage,
                initialPromptAttachments: attachments,
                initialPromptMetadata: providerMetadata,
                allowedDirectories: claudeAppShotDirectoriesIfNeeded(appShots: appShots),
                initialGoal: initialGoal,
                settingsSource: .nextTurn
            ))
            try completeInitialPromptSetup(
                thread: thread,
                stagedContext: snapshot.stagedContext,
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

    private func completeInitialPromptSetup(
        thread: AgentThread,
        stagedContext: String?,
        existingLocalUserMessageID: String?
    ) throws {
        thread.hasCompletedInitialSetup = true
        try modelContext.save()
        state.lastTurnInterrupted = false
        state.isCancellingTurn = false
        state.lastTurnError = nil
        state.activeRuntimeActivityTurnId = nil
        clearConsumedPendingRestoreContext(using: stagedContext)
        markVisibleTurnStarted()
        state.turnState.beginTurn()
        recordInitialPromptOutboundActivity()
        if let existingLocalUserMessageID {
            state.clearRetryableFailedMessage(id: existingLocalUserMessageID)
        }
        state.respawnAttempts = 0
    }

    func createInitialWorkingDirectory(
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

    func rollbackFailedInitialSetup(
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

}
