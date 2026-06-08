import Foundation

enum SessionSettingsConfigSource {
    case currentContinuation
    case nextTurn
}

private struct SpawnSettingsContext {
    let liveConfig: AgentSpawnConfig?
    let currentContinuationSnapshot: SessionSettingsSnapshot?
}

extension ConversationViewModel {
    func makeSpawnConfig(
        workingDirectory overrideWorkingDirectory: String? = nil,
        initialPrompt: String? = nil,
        settingsSource: SessionSettingsConfigSource = .nextTurn
    ) throws -> AgentSpawnConfig {
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }

        let settingsContext = spawnSettingsContext(settingsSource: settingsSource)
        let providerId = settingsContext.liveConfig?.providerId ?? dbConversation.provider ?? settingsService.current.defaultProvider
        let workingDirectory = overrideWorkingDirectory
            ?? settingsContext.liveConfig?.workingDirectory
            ?? dbConversation.thread?.worktreePath
            ?? dbConversation.thread?.project?.path

        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AgentError.spawnFailed("Cannot spawn agent: no working directory")
        }

        let permissionModeOverride = spawnPermissionModeOverride(settingsSource: settingsSource, context: settingsContext)
        let planModeOverride = spawnPlanModeOverride(settingsSource: settingsSource, context: settingsContext)
        let modelAndEffort = spawnModelAndEffort(context: settingsContext, thread: dbConversation.thread)

        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: nonPlanPermissionMode(permissionModeOverride ?? dbConversation.thread?.permissionMode),
            planModeEnabled: planModeOverride ?? dbConversation.thread?.planModeEnabled ?? false,
            model: modelAndEffort.model,
            effort: modelAndEffort.effort,
            initialPrompt: initialPrompt
        )
    }

    func pendingPermissionModeForDisplay() -> String? {
        state.pendingSessionSettingsChange?.pending.permissionMode
    }

    func pendingPlanModeForDisplay() -> Bool? {
        state.pendingSessionSettingsChange?.pending.planModeEnabled
    }

    func applyPendingSessionSettingsForNextTurn() async throws {
        guard let pending = state.pendingSessionSettingsChange else {
            return
        }
        guard pending.hasAnyChange else {
            state.pendingSessionSettingsChange = nil
            return
        }

        let config = try makeSpawnConfig(settingsSource: .nextTurn)
        do {
            let result = try await reconfigureSession(config: config)
            guard result != .nextTurnRequired else {
                return
            }
            finishPendingSessionSettingsApply(pending: pending, config: config)
        } catch {
            rollbackPendingSessionSettings(pending)
            state.lastTurnError = error.localizedDescription
            throw error
        }
    }

    func applyPendingSessionSettingsBeforeNextOutboundTurn() async throws {
        guard state.pendingSessionSettingsChange != nil else {
            return
        }

        try ensureCanReserveOutbound()
        try await applyPendingSessionSettingsForNextTurn()
    }

    func finishPendingSessionSettingsApply(
        pending: PendingSessionSettingsChange,
        config: AgentSpawnConfig,
        recordsContextWindowInvalidation: Bool = true
    ) {
        if pending.hasPermissionModeChange {
            state.runtimePermissionMode = pending.pending.permissionMode
            state.lastNonPlanPermissionMode = pending.pending.permissionMode
        }
        if pending.hasPlanModeChange {
            state.runtimePlanModeEnabled = pending.pending.planModeEnabled
        }

        state.liveSessionConfig = config
        state.pendingSessionSettingsChange = nil

        if recordsContextWindowInvalidation && pending.invalidatesContextWindow {
            recordContextWindowInvalidation()
        }
    }

    func rollbackPendingSessionSettings(_ pending: PendingSessionSettingsChange) {
        guard let dbThread = dbThread() else {
            state.pendingSessionSettingsChange = nil
            return
        }

        if pending.hasModelChange {
            dbThread.model = pending.original.model
        }
        if pending.hasEffortChange {
            dbThread.effort = pending.original.effort
        }
        if pending.hasPermissionModeChange {
            dbThread.permissionMode = pending.original.permissionMode
        }
        if pending.hasPlanModeChange {
            dbThread.planModeEnabled = pending.original.planModeEnabled
        }
        state.pendingSessionSettingsChange = nil
        try? modelContext.save()
    }

    func finishFreshSessionSettingsApply(
        pending: PendingSessionSettingsChange?,
        config: AgentSpawnConfig
    ) {
        if let pending {
            finishPendingSessionSettingsApply(
                pending: pending,
                config: config,
                recordsContextWindowInvalidation: false
            )
        } else {
            state.liveSessionConfig = config
        }
    }
}

extension ConversationViewModel {
    func preparePendingSnapshotIfNeeded(for dbThread: AgentThread) -> SessionSettingsSnapshot {
        let snapshot = sessionSettingsSnapshot(for: dbThread)
        if shouldStageSessionSettingChange {
            ensurePendingSessionSettingsChange(dbThread: dbThread)
        }
        return snapshot
    }

    func ensurePendingSessionSettingsChange(dbThread: AgentThread) {
        guard state.pendingSessionSettingsChange == nil else {
            return
        }

        let snapshot = sessionSettingsSnapshot(for: dbThread)
        state.pendingSessionSettingsChange = PendingSessionSettingsChange(
            original: snapshot,
            pending: snapshot,
            liveSessionConfig: state.liveSessionConfig
        )
    }

    func preparePlanModePendingSnapshotIfNeeded(
        for dbThread: AgentThread,
        displayedValue: Bool
    ) -> SessionSettingsSnapshot {
        var snapshot = sessionSettingsSnapshot(for: dbThread)
        snapshot.planModeEnabled = displayedValue
        guard shouldStageSessionSettingChange else {
            return snapshot
        }

        if let pending = state.pendingSessionSettingsChange {
            guard !pending.hasPlanModeChange else {
                return snapshot
            }
            var original = pending.original
            original.planModeEnabled = displayedValue
            state.pendingSessionSettingsChange = PendingSessionSettingsChange(
                original: original,
                pending: pending.pending,
                liveSessionConfig: pending.liveSessionConfig,
                invalidatesContextWindow: pending.invalidatesContextWindow
            )
        } else {
            state.pendingSessionSettingsChange = PendingSessionSettingsChange(
                original: snapshot,
                pending: snapshot,
                liveSessionConfig: state.liveSessionConfig
            )
        }
        return snapshot
    }

    func displayedPlanModeSetting(for dbThread: AgentThread) -> Bool {
        state.pendingSessionSettingsChange?.pending.planModeEnabled
            ?? state.runtimePlanModeEnabled
            ?? dbThread.planModeEnabled
            ?? false
    }

    func refreshPendingSessionSettingsChange(
        from dbThread: AgentThread,
        invalidatesContextWindow: Bool = false
    ) {
        guard var pending = state.pendingSessionSettingsChange else {
            return
        }

        pending.pending = sessionSettingsSnapshot(for: dbThread)
        pending.invalidatesContextWindow = (pending.invalidatesContextWindow || invalidatesContextWindow) &&
            pending.hasModelChange

        state.pendingSessionSettingsChange = pending.hasAnyChange ? pending : nil
    }

    func stagePendingSessionSettingsChange(
        original: SessionSettingsSnapshot,
        dbThread: AgentThread,
        invalidatesContextWindow: Bool = false
    ) {
        var pending = PendingSessionSettingsChange(
            original: original,
            pending: sessionSettingsSnapshot(for: dbThread),
            liveSessionConfig: state.liveSessionConfig
        )
        pending.invalidatesContextWindow = invalidatesContextWindow && pending.hasModelChange
        state.pendingSessionSettingsChange = pending.hasAnyChange ? pending : nil
    }

    func finishStagedSettingsIfNeeded(dbThread: AgentThread, invalidatesContextWindow: Bool = false) -> Bool {
        guard shouldStageSessionSettingChange else {
            return false
        }
        // Active turns and deferred approvals keep their current provider settings;
        // the persisted settings are staged into the next turn's spawn config.
        refreshPendingSessionSettingsChange(from: dbThread, invalidatesContextWindow: invalidatesContextWindow)
        return true
    }

    func saveSettingsChange(dbThread: AgentThread, rollback: () -> Void) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            rollback()
            if shouldStageSessionSettingChange {
                refreshPendingSessionSettingsChange(from: dbThread)
            }
            state.lastTurnError = error.localizedDescription
            return false
        }
    }

    func reconfigureSettingsTask(
        original: SessionSettingsSnapshot,
        dbThread: AgentThread,
        invalidatesContextWindow: Bool = false,
        rollback: @escaping () -> Void,
        onNextTurnRequired: @escaping () -> Void = {},
        onApplied: @escaping () -> Void = {}
    ) -> Task<Void, Never> {
        Task { @MainActor [self] in
            await reconfigureSessionSettingChange(
                original: original,
                dbThread: dbThread,
                invalidatesContextWindow: invalidatesContextWindow,
                onApplied: onApplied,
                onNextTurnRequired: onNextTurnRequired,
                onFailure: rollback
            )
        }
    }

    func reconfigureSessionSettingChange(
        original: SessionSettingsSnapshot,
        dbThread: AgentThread,
        invalidatesContextWindow: Bool = false,
        onApplied: () -> Void = {},
        onNextTurnRequired: () -> Void = {},
        onFailure: () -> Void
    ) async {
        do {
            let result = try await reconfigureSession()
            if result == .nextTurnRequired {
                onNextTurnRequired()
                stagePendingSessionSettingsChange(
                    original: original,
                    dbThread: dbThread,
                    invalidatesContextWindow: invalidatesContextWindow
                )
            } else {
                onApplied()
            }
        } catch {
            onFailure()
            try? modelContext.save()
            state.lastTurnError = error.localizedDescription
        }
    }
}

extension ConversationViewModel {
    func sessionSettingsSnapshot(for dbThread: AgentThread) -> SessionSettingsSnapshot {
        SessionSettingsSnapshot(
            model: dbThread.model,
            effort: dbThread.effort,
            permissionMode: dbThread.permissionMode,
            planModeEnabled: dbThread.planModeEnabled ?? false,
            runtimePermissionMode: state.runtimePermissionMode,
            runtimePlanModeEnabled: state.runtimePlanModeEnabled,
            lastNonPlanPermissionMode: state.lastNonPlanPermissionMode
        )
    }

    private func spawnSettingsContext(settingsSource: SessionSettingsConfigSource) -> SpawnSettingsContext {
        guard settingsSource == .currentContinuation else {
            return SpawnSettingsContext(liveConfig: nil, currentContinuationSnapshot: nil)
        }
        return SpawnSettingsContext(
            liveConfig: state.pendingSessionSettingsChange?.liveSessionConfig ?? state.liveSessionConfig,
            currentContinuationSnapshot: state.pendingSessionSettingsChange?.original
        )
    }

    private func spawnPermissionModeOverride(
        settingsSource: SessionSettingsConfigSource,
        context: SpawnSettingsContext
    ) -> String? {
        if settingsSource == .currentContinuation {
            return state.runtimePermissionMode
                ?? context.liveConfig?.permissionMode
                ?? context.currentContinuationSnapshot?.permissionMode
        }
        if let pendingSettings = state.pendingSessionSettingsChange,
           pendingSettings.hasPermissionModeChange {
            return pendingSettings.pending.permissionMode
        }
        return state.runtimePermissionMode
    }

    private func spawnPlanModeOverride(
        settingsSource: SessionSettingsConfigSource,
        context: SpawnSettingsContext
    ) -> Bool? {
        if state.pendingToolApproval?.request.toolName == "ExitPlanMode" {
            return true
        }
        if settingsSource == .currentContinuation {
            return state.runtimePlanModeEnabled
                ?? context.liveConfig?.planModeEnabled
                ?? context.currentContinuationSnapshot?.runtimePlanModeEnabled
                ?? context.currentContinuationSnapshot?.planModeEnabled
        }
        if let pendingSettings = state.pendingSessionSettingsChange,
           pendingSettings.hasPlanModeChange {
            return pendingSettings.pending.planModeEnabled
        }
        return state.runtimePlanModeEnabled
    }

    private func spawnModelAndEffort(context: SpawnSettingsContext, thread: AgentThread?) -> (model: String?, effort: String?) {
        if let liveConfig = context.liveConfig {
            return (liveConfig.model, liveConfig.effort)
        }
        return (
            context.currentContinuationSnapshot?.model ?? thread?.model,
            AppSettings.normalizedEffortLevel(context.currentContinuationSnapshot?.effort ?? thread?.effort)
        )
    }
}
