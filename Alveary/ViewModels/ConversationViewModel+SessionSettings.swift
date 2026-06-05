import Foundation

enum SessionSettingsConfigSource {
    case currentContinuation
    case nextTurn
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

        let liveConfig = settingsSource == .currentContinuation
            ? state.pendingSessionSettingsChange?.liveSessionConfig ?? state.liveSessionConfig
            : nil
        let currentContinuationSnapshot = settingsSource == .currentContinuation
            ? state.pendingSessionSettingsChange?.original
            : nil
        let providerId = liveConfig?.providerId ?? dbConversation.provider ?? settingsService.current.defaultProvider
        let workingDirectory = overrideWorkingDirectory
            ?? liveConfig?.workingDirectory
            ?? dbConversation.thread?.worktreePath
            ?? dbConversation.thread?.project?.path

        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AgentError.spawnFailed("Cannot spawn agent: no working directory")
        }

        let permissionModeOverride: String?
        if state.pendingToolApproval?.request.toolName == "ExitPlanMode" {
            permissionModeOverride = "plan"
        } else if settingsSource == .currentContinuation {
            permissionModeOverride = state.runtimePermissionMode
                ?? liveConfig?.permissionMode
                ?? currentContinuationSnapshot?.permissionMode
        } else if let pendingSettings = state.pendingSessionSettingsChange,
                  pendingSettings.hasPermissionModeChange {
            permissionModeOverride = pendingSettings.pending.permissionMode
        } else {
            permissionModeOverride = state.runtimePermissionMode
        }

        let model: String?
        let effort: String?
        if let liveConfig {
            model = liveConfig.model
            effort = liveConfig.effort
        } else {
            model = currentContinuationSnapshot?.model ?? dbConversation.thread?.model
            effort = AppSettings.normalizedEffortLevel(currentContinuationSnapshot?.effort ?? dbConversation.thread?.effort)
        }

        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: permissionModeOverride ?? dbConversation.thread?.permissionMode,
            model: model,
            effort: effort,
            initialPrompt: initialPrompt
        )
    }

    func pendingPermissionModeForDisplay() -> String? {
        state.pendingSessionSettingsChange?.pending.permissionMode
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
            try await reconfigureSession(config: config)
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
            if pending.pending.permissionMode == "plan" {
                state.lastNonPlanPermissionMode = pending.original.permissionMode == "plan"
                    ? pending.original.lastNonPlanPermissionMode
                    : pending.original.permissionMode
            } else {
                state.lastNonPlanPermissionMode = pending.pending.permissionMode
            }
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
}

private extension ConversationViewModel {
    func sessionSettingsSnapshot(for dbThread: AgentThread) -> SessionSettingsSnapshot {
        SessionSettingsSnapshot(
            model: dbThread.model,
            effort: dbThread.effort,
            permissionMode: dbThread.permissionMode,
            runtimePermissionMode: state.runtimePermissionMode,
            lastNonPlanPermissionMode: state.lastNonPlanPermissionMode
        )
    }
}
