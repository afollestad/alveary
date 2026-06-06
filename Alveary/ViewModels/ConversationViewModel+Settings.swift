import AgentCLIKit
import Foundation
import SwiftData

private struct PermissionRuntimeStateSnapshot {
    let runtimePermissionMode: String?
    let runtimePlanModeEnabled: Bool?
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
        isAgentActivelyWorking || state.pendingToolApproval != nil || hasUnansweredPrompt
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
        state.runtimePermissionMode = newPermissionMode
        state.runtimePlanModeEnabled = false
        state.lastNonPlanPermissionMode = newPermissionMode
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            snapshot.restore(conversation: dbConversation, thread: dbThread, state: state)
            state.lastTurnError = error.localizedDescription
        }
    }

    @discardableResult
    func applyModelChange(
        _ newValue: String,
        effortOptions: [AgentCLIKit.AgentProviderOption] = [],
        defaultEffort: String? = nil
    ) -> Task<Void, Never> {
        guard canApplySettingsChange,
              let dbThread = activeSettingsThread() else {
            return .noop
        }

        let previousValue = dbThread.model ?? AppSettings.defaultModelValue
        guard previousValue != newValue else { return .noop }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
        let previousEffort = dbThread.effort
        dbThread.model = newValue == AppSettings.defaultModelValue ? nil : newValue
        resetEffortIfNeeded(for: dbThread, effortOptions: effortOptions, defaultEffort: defaultEffort)
        state.lastTurnError = nil

        guard saveSettingsChange(dbThread: dbThread, rollback: {
            dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
            dbThread.effort = previousEffort
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
        guard previousValue != newValue else { return .noop }

        let original = preparePendingSnapshotIfNeeded(for: dbThread)
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

    func preparePendingSnapshotIfNeeded(for dbThread: AgentThread) -> SessionSettingsSnapshot {
        let snapshot = sessionSettingsSnapshot(for: dbThread)
        if shouldStageSessionSettingChange {
            ensurePendingSessionSettingsChange(dbThread: dbThread)
        }
        return snapshot
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

    func resetEffortIfNeeded(
        for dbThread: AgentThread,
        effortOptions: [AgentCLIKit.AgentProviderOption],
        defaultEffort: String?
    ) {
        guard !effortOptions.isEmpty else {
            return
        }

        let supportsCurrentEffort = effortOptions.contains { $0.value == dbThread.effort }
        guard !supportsCurrentEffort || dbThread.effort == AppSettings.defaultEffortLevel else {
            return
        }

        dbThread.effort = defaultEffort ?? effortOptions.first?.value ?? AppSettings.defaultEffortLevel
    }

    func permissionRuntimeStateSnapshot() -> PermissionRuntimeStateSnapshot {
        PermissionRuntimeStateSnapshot(
            runtimePermissionMode: state.runtimePermissionMode,
            runtimePlanModeEnabled: state.runtimePlanModeEnabled,
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
        state.lastNonPlanPermissionMode = snapshot.lastNonPlanPermissionMode
    }
}

private struct ProviderSettingSnapshot {
    let provider: String?
    let model: String?
    let permissionMode: String
    let planModeEnabled: Bool?
    let effort: String
    let runtimePermissionMode: String?
    let runtimePlanModeEnabled: Bool?
    let lastNonPlanPermissionMode: String?

    @MainActor
    init(conversation: Conversation, thread: AgentThread, state: ConversationState) {
        provider = conversation.provider
        model = thread.model
        permissionMode = thread.permissionMode
        planModeEnabled = thread.planModeEnabled
        effort = thread.effort
        runtimePermissionMode = state.runtimePermissionMode
        runtimePlanModeEnabled = state.runtimePlanModeEnabled
        lastNonPlanPermissionMode = state.lastNonPlanPermissionMode
    }

    @MainActor
    func restore(conversation: Conversation, thread: AgentThread, state: ConversationState) {
        conversation.provider = provider
        thread.model = model
        thread.permissionMode = permissionMode
        thread.planModeEnabled = planModeEnabled
        thread.effort = effort
        state.runtimePermissionMode = runtimePermissionMode
        state.runtimePlanModeEnabled = runtimePlanModeEnabled
        state.lastNonPlanPermissionMode = lastNonPlanPermissionMode
    }
}

private extension Task where Success == Void, Failure == Never {
    static var noop: Task<Void, Never> { Task {} }
}
