import Foundation

extension ConversationViewModel {
    var effectivePermissionMode: String {
        nonPlanPermissionMode(
            state.runtimePermissionMode
                ?? state.pendingSessionSettingsChange?.original.permissionMode
                ?? dbConversation()?.thread?.permissionMode
        )
    }

    var effectivePlanModeEnabled: Bool {
        state.runtimePlanModeEnabled
            ?? state.pendingSessionSettingsChange?.original.planModeEnabled
            ?? dbConversation()?.thread?.planModeEnabled
            ?? false
    }

    func syncRuntimePermissionMode(_ permissionMode: String) {
        if permissionMode == "plan" {
            syncRuntimePlanMode(true)
            state.runtimePermissionMode = state.lastNonPlanPermissionMode
                ?? nonPlanPermissionMode(dbConversation()?.thread?.permissionMode)
            return
        }

        state.runtimePermissionMode = permissionMode
        state.lastNonPlanPermissionMode = permissionMode
        guard state.pendingSessionSettingsChange?.hasPermissionModeChange != true,
              let thread = dbThread(),
              thread.permissionMode != permissionMode else {
            return
        }

        thread.permissionMode = permissionMode
        do {
            try modelContext.save()
        } catch {
            // Best-effort: the live runtime state remains authoritative even if
            // the persisted picker state lags until the next successful save.
        }
    }

    func syncRuntimePlanMode(_ isEnabled: Bool) {
        state.runtimePlanModeEnabled = isEnabled
        guard state.pendingSessionSettingsChange?.hasPlanModeChange != true,
              let thread = dbThread(),
              thread.planModeEnabled != isEnabled else {
            return
        }

        thread.planModeEnabled = isEnabled
        do {
            try modelContext.save()
        } catch {
            // Best-effort: the runtime event already reflects provider state.
        }
    }

    func nonPlanPermissionMode(_ permissionMode: String?) -> String {
        if let permissionMode, permissionMode != "plan" {
            return permissionMode
        }
        if let lastNonPlanPermissionMode = state.lastNonPlanPermissionMode,
           lastNonPlanPermissionMode != "plan" {
            return lastNonPlanPermissionMode
        }
        if let storedMode = dbConversation()?.thread?.permissionMode,
           storedMode != "plan" {
            return storedMode
        }
        let providerId = dbConversation()?.provider ?? settingsService.current.defaultProvider
        return AppSettings.defaultPermissionMode(forProvider: providerId)
    }
}
