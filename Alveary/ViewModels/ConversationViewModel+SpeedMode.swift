import Foundation

extension ConversationViewModel {
    @discardableResult
    func applySpeedModeChange(_ newValue: AgentSpeedMode, supportsSpeedMode: Bool = true) -> Task<Void, Never> {
        guard canApplySettingsChange,
              let dbThread = dbThread() else {
            return Task {}
        }

        guard newValue != .fast || supportsSpeedMode else {
            state.lastTurnError = "Fast mode is not supported by this provider."
            return Task {}
        }

        let previousValue = dbThread.speedMode
        let previousRuntimeSpeedMode = state.runtimeSpeedMode
        let displayedValue = displayedSpeedModeSetting(for: dbThread)
        guard displayedValue != newValue else { return Task {} }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
        dbThread.speedMode = newValue.rawValue
        if !shouldStageSessionSettingChange {
            state.runtimeSpeedMode = newValue
        }
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: {
            dbThread.speedMode = previousValue
            self.state.runtimeSpeedMode = previousRuntimeSpeedMode
        }) else {
            return Task {}
        }
        guard !finishStagedSettingsIfNeeded(dbThread: dbThread),
              shouldReconfigureOnSettingChange() else {
            return Task {}
        }

        return reconfigureSettingsTask(original: original, dbThread: dbThread) {
            dbThread.speedMode = previousValue
            self.state.runtimeSpeedMode = previousRuntimeSpeedMode
        } onNextTurnRequired: {
            self.state.runtimeSpeedMode = previousRuntimeSpeedMode
        }
    }

    func ensureSpeedModeEnabledForOutbound(supportsSpeedMode: Bool = true) async throws {
        try await ensureSpeedModeForOutbound(.fast, supportsSpeedMode: supportsSpeedMode)
    }

    func ensureSpeedModeForOutbound(_ speedMode: AgentSpeedMode, supportsSpeedMode: Bool = true) async throws {
        await applySpeedModeChange(speedMode, supportsSpeedMode: supportsSpeedMode).value
        guard (pendingSpeedModeForDisplay() ?? dbThread()?.normalizedSpeedMode ?? .standard) == speedMode else {
            throw AgentError.spawnFailed(lastTurnError ?? "Failed to enable fast mode")
        }
    }

    func normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: Bool) {
        guard !supportsSpeedMode,
              canApplySettingsChange,
              let dbThread = dbThread(),
              dbThread.normalizedSpeedMode == .fast else {
            return
        }

        let previousValue = dbThread.speedMode
        dbThread.speedMode = AgentSpeedMode.standard.rawValue
        state.runtimeSpeedMode = .standard
        state.lastTurnError = nil
        do {
            try modelContext.save()
        } catch {
            dbThread.speedMode = previousValue
            state.lastTurnError = error.localizedDescription
        }
    }
}
