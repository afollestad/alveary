import AgentCLIKit
import Foundation
import SwiftData

private struct PermissionRuntimeStateSnapshot {
    let runtimePermissionMode: String?
    let runtimePlanModeEnabled: Bool?
    let runtimeSpeedMode: AgentSpeedMode?
    let lastNonPlanPermissionMode: String?
}

extension ConversationViewModel {
    // The model, effort, permission, and plan-mode controls stay editable during active turns.
    // Those writes persist immediately but are staged for the next new turn.
    var canApplySettingsChange: Bool {
        !state.isSendingMessage &&
            !state.hasActiveSessionHandoff &&
            !state.isReconfiguringSession &&
            !state.isCancellingInitialSetup &&
            setupPhase == nil
    }

    var canApplyPreStartupSettingChange: Bool {
        canApplySettingsChange &&
            !isAgentActivelyWorking &&
            state.pendingToolApproval == nil &&
            !hasUnansweredPrompt
    }

    var shouldStageSessionSettingChange: Bool {
        isAgentActivelyWorking ||
            state.pendingToolApproval != nil ||
            hasUnansweredPrompt ||
            shouldStageInactiveClaudeSettings
    }

    var shouldStageInactiveClaudeSettings: Bool {
        let providerId = dbConversation()?.provider ?? settingsService.current.defaultProvider
        return providerId == "claude" &&
            !state.turnState.isActive &&
            shouldReconfigureOnSettingChange()
    }

    func shouldReconfigureOnSettingChange() -> Bool {
        conversation.thread?.hasCompletedInitialSetup == true
    }

    func applyProviderChange(_ newValue: String) {
        guard canApplyPreStartupSettingChange,
              AppSettings.supportedProviderIDs.contains(newValue),
              let dbConversation = modelContext.resolveConversation(id: conversationModelID),
              let dbThread = dbConversation.thread,
              !dbThread.hasCompletedInitialSetup else {
            return
        }

        let snapshot = ProviderSettingSnapshot(conversation: dbConversation, thread: dbThread, state: state)
        let newPermissionMode = AppSettings.defaultPermissionMode(forProvider: newValue)
        let currentProvider = snapshot.provider ?? settingsService.current.defaultProvider
        guard currentProvider != newValue || snapshot.model != nil || snapshot.permissionMode != newPermissionMode else {
            return
        }

        dbConversation.provider = newValue
        dbThread.model = nil
        dbThread.permissionMode = newPermissionMode
        dbThread.planModeEnabled = false
        dbThread.effort = AppSettings.defaultEffortLevel
        dbThread.speedMode = AgentSpeedMode.standard.rawValue
        state.runtimePermissionMode = newPermissionMode
        state.runtimePlanModeEnabled = false
        state.runtimeSpeedMode = .standard
        state.lastNonPlanPermissionMode = newPermissionMode
        state.lastTurnError = nil

        do {
            try modelContext.save()
            clearPendingExitPlanModeDenialState()
        } catch {
            snapshot.restore(conversation: dbConversation, thread: dbThread, state: state)
            state.lastTurnError = error.localizedDescription
        }
    }

    @discardableResult
    func applyPreStartupProviderModelChange(
        providerID: String,
        model: String,
        effortOptions: [AgentCLIKit.AgentProviderOption],
        defaultEffort: String?,
        supportsSpeedMode: Bool = true
    ) -> Bool {
        guard canApplyPreStartupSettingChange,
              AppSettings.supportedProviderIDs.contains(providerID),
              let dbConversation = modelContext.resolveConversation(id: conversationModelID),
              let dbThread = dbConversation.thread,
              !dbThread.hasCompletedInitialSetup else {
            return false
        }

        let snapshot = ProviderSettingSnapshot(conversation: dbConversation, thread: dbThread, state: state)
        let storedModel = model == AppSettings.defaultModelValue ? nil : model
        let currentProvider = snapshot.provider ?? settingsService.current.defaultProvider
        let providerChanged = currentProvider != providerID
        let newPermissionMode = AppSettings.defaultPermissionMode(forProvider: providerID)
        let newEffort = supportedOrDefaultEffort(
            currentEffort: dbThread.effort,
            effortOptions: effortOptions,
            defaultEffort: defaultEffort
        )
        let newSpeedMode = supportsSpeedMode ? dbThread.normalizedSpeedMode : .standard
        let runtimeSpeedModeChanged = snapshot.runtimeSpeedMode != newSpeedMode
        guard providerChanged ||
            snapshot.model != storedModel ||
            snapshot.effort != newEffort ||
            snapshot.speedMode != newSpeedMode ||
            runtimeSpeedModeChanged ||
            (providerChanged && snapshot.permissionMode != newPermissionMode) else {
            return true
        }

        // Pre-start provider switches must save the provider, model, default
        // permission, plan mode, and effort together so the first spawn sees a
        // coherent agent configuration.
        dbConversation.provider = providerID
        dbThread.model = storedModel
        dbThread.effort = newEffort
        dbThread.speedMode = newSpeedMode.rawValue
        state.runtimeSpeedMode = newSpeedMode
        if providerChanged {
            dbThread.permissionMode = newPermissionMode
            dbThread.planModeEnabled = false
            state.runtimePermissionMode = newPermissionMode
            state.runtimePlanModeEnabled = false
            state.lastNonPlanPermissionMode = newPermissionMode
        }
        state.lastTurnError = nil

        do {
            try modelContext.save()
            if providerChanged { clearPendingExitPlanModeDenialState() }
            return true
        } catch {
            snapshot.restore(conversation: dbConversation, thread: dbThread, state: state)
            state.lastTurnError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func applyModelChange(
        _ newValue: String,
        effortOptions: [AgentCLIKit.AgentProviderOption] = [],
        defaultEffort: String? = nil,
        supportsSpeedMode: Bool = true
    ) -> Task<Void, Never> {
        guard canApplySettingsChange,
              let dbThread = activeSettingsThread() else {
            return .noop
        }

        let previousValue = dbThread.model ?? AppSettings.defaultModelValue
        guard previousValue != newValue else { return .noop }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
        let previousEffort = dbThread.effort
        let previousSpeedMode = dbThread.speedMode
        dbThread.model = newValue == AppSettings.defaultModelValue ? nil : newValue
        resetEffortIfNeeded(for: dbThread, effortOptions: effortOptions, defaultEffort: defaultEffort)
        normalizeSpeedModeIfUnsupported(for: dbThread, supportsSpeedMode: supportsSpeedMode)
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: {
            dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
            dbThread.effort = previousEffort
            dbThread.speedMode = previousSpeedMode
        }) else {
            return .noop
        }
        guard !finishStagedSettingsIfNeeded(dbThread: dbThread, invalidatesContextWindow: true),
              shouldReconfigureOnSettingChange() else {
            return .noop
        }

        return reconfigureSettingsTask(original: original, dbThread: dbThread, invalidatesContextWindow: true) {
            dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
            dbThread.effort = previousEffort
            dbThread.speedMode = previousSpeedMode
        } onApplied: {
            self.recordContextWindowInvalidation()
        }
    }

    @discardableResult
    func applyEffortChange(_ newValue: String) -> Task<Void, Never> {
        guard canApplySettingsChange,
              let dbThread = activeSettingsThread() else {
            return .noop
        }

        let previousValue = dbThread.effort
        guard previousValue != newValue else { return .noop }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
        dbThread.effort = newValue
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: { dbThread.effort = previousValue }) else {
            return .noop
        }
        guard !finishStagedSettingsIfNeeded(dbThread: dbThread),
              shouldReconfigureOnSettingChange() else {
            return .noop
        }

        return reconfigureSettingsTask(original: original, dbThread: dbThread) {
            dbThread.effort = previousValue
        }
    }

    @discardableResult
    func applyPermissionModeChange(_ newValue: String) -> Task<Void, Never> {
        guard canApplySettingsChange,
              canSelectPermissionMode(newValue),
              let dbThread = activeSettingsThread() else {
            return .noop
        }

        let previousValue = dbThread.permissionMode
        guard previousValue != newValue else { return .noop }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
        let previousRuntimeState = permissionRuntimeStateSnapshot()
        dbThread.permissionMode = newValue
        if !shouldStageSessionSettingChange {
            applyImmediatePermissionRuntimeState(newValue)
        }
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: {
            dbThread.permissionMode = previousValue
            self.restorePermissionRuntimeState(previousRuntimeState)
        }) else {
            return .noop
        }
        guard !finishStagedSettingsIfNeeded(dbThread: dbThread),
              shouldReconfigureOnSettingChange() else {
            return .noop
        }

        return reconfigureSettingsTask(original: original, dbThread: dbThread) {
            dbThread.permissionMode = previousValue
            self.restorePermissionRuntimeState(previousRuntimeState)
        } onNextTurnRequired: {
            self.restorePermissionRuntimeState(previousRuntimeState)
        }
    }

    @discardableResult
    func applyPlanModeChange(_ newValue: Bool) -> Task<Void, Never> {
        guard canApplySettingsChange,
              let dbThread = activeSettingsThread() else {
            return .noop
        }

        let previousValue = dbThread.planModeEnabled
        let displayedValue = displayedPlanModeSetting(for: dbThread)
        guard displayedValue != newValue else { return .noop }

        let original = preparePlanModePendingSnapshotIfNeeded(
            for: dbThread,
            displayedValue: displayedValue
        )
        let previousRuntimePlanModeEnabled = state.runtimePlanModeEnabled
        dbThread.planModeEnabled = newValue
        if !shouldStageSessionSettingChange {
            state.runtimePlanModeEnabled = newValue
            if newValue {
                state.lastNonPlanPermissionMode = nonPlanPermissionMode(dbThread.permissionMode)
            }
        }
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: {
            dbThread.planModeEnabled = previousValue
            self.state.runtimePlanModeEnabled = previousRuntimePlanModeEnabled
        }) else {
            return .noop
        }
        if !newValue {
            clearPendingExitPlanModeDenialState()
        }
        guard !finishStagedSettingsIfNeeded(dbThread: dbThread),
              shouldReconfigureOnSettingChange() else {
            return .noop
        }

        return reconfigureSettingsTask(original: original, dbThread: dbThread) {
            dbThread.planModeEnabled = previousValue
            self.state.runtimePlanModeEnabled = previousRuntimePlanModeEnabled
        } onNextTurnRequired: {
            self.state.runtimePlanModeEnabled = previousRuntimePlanModeEnabled
        }
    }

    func togglePlanModeForOutbound() async throws -> Bool {
        let target = !(pendingPlanModeForDisplay() ?? effectivePlanModeEnabled)
        try await ensurePlanModeForOutbound(target)
        return target
    }

    func ensurePlanModeEnabledForOutbound() async throws {
        try await ensurePlanModeForOutbound(true)
    }

    func ensurePlanModeForOutbound(_ isEnabled: Bool) async throws {
        await applyPlanModeChange(isEnabled).value
        guard (pendingPlanModeForDisplay() ?? effectivePlanModeEnabled) == isEnabled else {
            let action = isEnabled ? "enable" : "disable"
            throw AgentError.spawnFailed(lastTurnError ?? "Failed to \(action) plan mode")
        }
    }

    func applyWorktreePreferenceChange(_ newValue: Bool) {
        guard canApplyPreStartupSettingChange,
              let dbThread = activeSettingsThread(),
              dbThread.project?.isGitRepository == true,
              !dbThread.hasCompletedInitialSetup else {
            return
        }

        let previousValue = dbThread.useWorktree
        guard previousValue != newValue else { return }

        dbThread.useWorktree = newValue
        do {
            try modelContext.save()
        } catch {
            dbThread.useWorktree = previousValue
            state.lastTurnError = error.localizedDescription
        }
    }

    func recordContextWindowInvalidation() {
        guard let dbConversation = modelContext.resolveConversation(id: conversationModelID) else {
            return
        }

        let record = ConversationEventRecord(
            type: ConversationEventRecord.contextWindowInvalidatedType,
            conversation: dbConversation
        )
        modelContext.insert(record)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(record)
            state.lastTurnError = error.localizedDescription
        }
    }
}

private extension ConversationViewModel {
    func activeSettingsThread() -> AgentThread? {
        guard let threadID = conversation.thread?.persistentModelID else {
            return nil
        }
        return modelContext.resolveThread(id: threadID)
    }

    func canSelectPermissionMode(_ value: String) -> Bool {
        let providerId = dbConversation()?.provider ?? settingsService.current.defaultProvider
        return AppSettings.supportedPermissionModes(forProvider: providerId).contains(value)
    }

    func resetEffortIfNeeded(
        for dbThread: AgentThread,
        effortOptions: [AgentCLIKit.AgentProviderOption],
        defaultEffort: String?
    ) {
        guard !effortOptions.isEmpty else {
            return
        }

        let supportsCurrentEffort = effortOptions.contains { $0.value == dbThread.effort }
        guard !supportsCurrentEffort else {
            return
        }

        dbThread.effort = defaultEffort ?? effortOptions.first?.value ?? AppSettings.defaultEffortLevel
    }

    func normalizeSpeedModeIfUnsupported(for dbThread: AgentThread, supportsSpeedMode: Bool) {
        guard !supportsSpeedMode,
              dbThread.normalizedSpeedMode == .fast else {
            return
        }
        dbThread.speedMode = AgentSpeedMode.standard.rawValue
        if !shouldStageSessionSettingChange {
            state.runtimeSpeedMode = .standard
        }
    }

    func supportedOrDefaultEffort(
        currentEffort: String,
        effortOptions: [AgentCLIKit.AgentProviderOption],
        defaultEffort: String?
    ) -> String {
        guard !effortOptions.isEmpty else {
            return currentEffort
        }
        if effortOptions.contains(where: { $0.value == currentEffort }) {
            return currentEffort
        }
        return defaultEffort ?? effortOptions.first?.value ?? AppSettings.defaultEffortLevel
    }

    func permissionRuntimeStateSnapshot() -> PermissionRuntimeStateSnapshot {
        PermissionRuntimeStateSnapshot(
            runtimePermissionMode: state.runtimePermissionMode,
            runtimePlanModeEnabled: state.runtimePlanModeEnabled,
            runtimeSpeedMode: state.runtimeSpeedMode,
            lastNonPlanPermissionMode: state.lastNonPlanPermissionMode
        )
    }

    func applyImmediatePermissionRuntimeState(_ newValue: String) {
        state.runtimePermissionMode = newValue
        state.lastNonPlanPermissionMode = newValue
    }

    func restorePermissionRuntimeState(_ snapshot: PermissionRuntimeStateSnapshot) {
        state.runtimePermissionMode = snapshot.runtimePermissionMode
        state.runtimePlanModeEnabled = snapshot.runtimePlanModeEnabled
        state.runtimeSpeedMode = snapshot.runtimeSpeedMode
        state.lastNonPlanPermissionMode = snapshot.lastNonPlanPermissionMode
    }
}

private struct ProviderSettingSnapshot {
    let provider: String?
    let model: String?
    let permissionMode: String
    let planModeEnabled: Bool?
    let effort: String
    let speedMode: AgentSpeedMode
    let runtimePermissionMode: String?
    let runtimePlanModeEnabled: Bool?
    let runtimeSpeedMode: AgentSpeedMode?
    let lastNonPlanPermissionMode: String?

    @MainActor
    init(conversation: Conversation, thread: AgentThread, state: ConversationState) {
        provider = conversation.provider
        model = thread.model
        permissionMode = thread.permissionMode
        planModeEnabled = thread.planModeEnabled
        effort = thread.effort
        speedMode = thread.normalizedSpeedMode
        runtimePermissionMode = state.runtimePermissionMode
        runtimePlanModeEnabled = state.runtimePlanModeEnabled
        runtimeSpeedMode = state.runtimeSpeedMode
        lastNonPlanPermissionMode = state.lastNonPlanPermissionMode
    }

    @MainActor
    func restore(conversation: Conversation, thread: AgentThread, state: ConversationState) {
        conversation.provider = provider
        thread.model = model
        thread.permissionMode = permissionMode
        thread.planModeEnabled = planModeEnabled
        thread.effort = effort
        thread.speedMode = speedMode.rawValue
        state.runtimePermissionMode = runtimePermissionMode
        state.runtimePlanModeEnabled = runtimePlanModeEnabled
        state.runtimeSpeedMode = runtimeSpeedMode
        state.lastNonPlanPermissionMode = lastNonPlanPermissionMode
    }
}

private extension Task where Success == Void, Failure == Never {
    static var noop: Task<Void, Never> { Task {} }
}
