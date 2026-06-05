import AgentCLIKit
import Foundation
import SwiftData

private struct PermissionRuntimeStateSnapshot {
    let runtimePermissionMode: String?
    let lastNonPlanPermissionMode: String?
}

extension ConversationViewModel {
    // The model/effort/permission pickers stay editable during active turns.
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

    // Reconfigure (fork the provider session) whenever the thread already has a
    // spawned session to fork from. Between turns the Claude process may have
    // exited in `-p` mode, so we cannot gate on a live process.
    func shouldReconfigureOnSettingChange() -> Bool {
        conversation.thread?.hasCompletedInitialSetup == true
    }

    // Each `apply*Change` runs its state/DB write synchronously so the SwiftUI
    // `Picker` binding sees the new value on the same render cycle as the
    // click, then returns a `Task` carrying the async fork (+ rollback).
    // Bindings discard the task; tests `await .value` to observe completion.

    func applyProviderChange(_ newValue: String) {
        guard canApplyPreStartupSettingChange,
              AppSettings.supportedProviderIDs.contains(newValue),
              let dbConversation = modelContext.resolveConversation(id: conversationModelID),
              let dbThread = dbConversation.thread,
              !dbThread.hasCompletedInitialSetup else {
            return
        }

        let previousProvider = dbConversation.provider
        let previousModel = dbThread.model
        let previousPermissionMode = dbThread.permissionMode
        let previousEffort = dbThread.effort
        let previousRuntimePermissionMode = state.runtimePermissionMode
        let previousLastNonPlanPermissionMode = state.lastNonPlanPermissionMode

        let newPermissionMode = AppSettings.defaultPermissionMode(forProvider: newValue)
        guard (previousProvider ?? settingsService.current.defaultProvider) != newValue ||
            previousModel != nil ||
            previousPermissionMode != newPermissionMode else {
            return
        }

        dbConversation.provider = newValue
        dbThread.model = nil
        dbThread.permissionMode = newPermissionMode
        dbThread.effort = AppSettings.defaultEffortLevel
        state.runtimePermissionMode = newPermissionMode
        state.lastNonPlanPermissionMode = newPermissionMode == "plan" ? nil : newPermissionMode
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbConversation.provider = previousProvider
            dbThread.model = previousModel
            dbThread.permissionMode = previousPermissionMode
            dbThread.effort = previousEffort
            state.runtimePermissionMode = previousRuntimePermissionMode
            state.lastNonPlanPermissionMode = previousLastNonPlanPermissionMode
            state.lastTurnError = error.localizedDescription
        }
    }

    @discardableResult
    func applyModelChange(
        _ newValue: String,
        effortOptions: [AgentCLIKit.AgentProviderOption] = [],
        defaultEffort: String? = nil
    ) -> Task<Void, Never> {
        guard canApplySettingsChange else { return .noop }
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.resolveThread(id: threadID) else {
            return .noop
        }

        let previousValue = dbThread.model ?? AppSettings.defaultModelValue
        guard previousValue != newValue else { return .noop }

        let shouldStage = shouldStageSessionSettingChange
        if shouldStage {
            ensurePendingSessionSettingsChange(dbThread: dbThread)
        }

        dbThread.model = newValue == AppSettings.defaultModelValue ? nil : newValue

        let previousEffort = dbThread.effort
        resetEffortIfNeeded(
            for: dbThread,
            effortOptions: effortOptions,
            defaultEffort: defaultEffort
        )

        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
            dbThread.effort = previousEffort
            if shouldStage {
                refreshPendingSessionSettingsChange(from: dbThread)
            }
            state.lastTurnError = error.localizedDescription
            return .noop
        }

        if shouldStage {
            refreshPendingSessionSettingsChange(from: dbThread, invalidatesContextWindow: true)
            return .noop
        }

        guard shouldReconfigureOnSettingChange() else { return .noop }

        return Task { @MainActor [self] in
            do {
                try await reconfigureSession()
                recordContextWindowInvalidation()
            } catch {
                dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
                dbThread.effort = previousEffort
                try? modelContext.save()
                state.lastTurnError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func applyEffortChange(_ newValue: String) -> Task<Void, Never> {
        guard canApplySettingsChange else { return .noop }
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.resolveThread(id: threadID) else {
            return .noop
        }

        let previousValue = dbThread.effort
        guard previousValue != newValue else { return .noop }

        let shouldStage = shouldStageSessionSettingChange
        if shouldStage {
            ensurePendingSessionSettingsChange(dbThread: dbThread)
        }

        dbThread.effort = newValue
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.effort = previousValue
            if shouldStage {
                refreshPendingSessionSettingsChange(from: dbThread)
            }
            state.lastTurnError = error.localizedDescription
            return .noop
        }

        if shouldStage {
            refreshPendingSessionSettingsChange(from: dbThread)
            return .noop
        }

        guard shouldReconfigureOnSettingChange() else { return .noop }

        return Task { @MainActor [self] in
            do {
                try await reconfigureSession()
            } catch {
                dbThread.effort = previousValue
                try? modelContext.save()
                state.lastTurnError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func applyPermissionModeChange(_ newValue: String) -> Task<Void, Never> {
        guard canApplySettingsChange else { return .noop }
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.resolveThread(id: threadID) else {
            return .noop
        }

        let previousValue = dbThread.permissionMode
        guard previousValue != newValue else { return .noop }

        let shouldStage = shouldStageSessionSettingChange
        if shouldStage {
            ensurePendingSessionSettingsChange(dbThread: dbThread)
        }

        let previousRuntimeState = permissionRuntimeStateSnapshot()
        dbThread.permissionMode = newValue
        if !shouldStage {
            applyImmediatePermissionRuntimeState(newValue, previousStoredMode: previousValue)
        }
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.permissionMode = previousValue
            restorePermissionRuntimeState(previousRuntimeState)
            if shouldStage {
                refreshPendingSessionSettingsChange(from: dbThread)
            }
            state.lastTurnError = error.localizedDescription
            return .noop
        }

        if shouldStage {
            refreshPendingSessionSettingsChange(from: dbThread)
            return .noop
        }

        guard shouldReconfigureOnSettingChange() else { return .noop }

        return Task { @MainActor [self] in
            do {
                try await reconfigureSession()
            } catch {
                dbThread.permissionMode = previousValue
                restorePermissionRuntimeState(previousRuntimeState)
                try? modelContext.save()
                state.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyWorktreePreferenceChange(_ newValue: Bool) {
        guard canApplyPreStartupSettingChange else { return }
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.resolveThread(id: threadID),
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
}

extension ConversationViewModel {
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

private extension Task where Success == Void, Failure == Never {
    static var noop: Task<Void, Never> { Task {} }
}

private extension ConversationViewModel {
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
            lastNonPlanPermissionMode: state.lastNonPlanPermissionMode
        )
    }

    func applyImmediatePermissionRuntimeState(_ newValue: String, previousStoredMode: String) {
        state.runtimePermissionMode = newValue
        if newValue == "plan" {
            if previousStoredMode != "plan" {
                state.lastNonPlanPermissionMode = previousStoredMode
            }
        } else {
            state.lastNonPlanPermissionMode = newValue
        }
    }

    func restorePermissionRuntimeState(_ snapshot: PermissionRuntimeStateSnapshot) {
        state.runtimePermissionMode = snapshot.runtimePermissionMode
        state.lastNonPlanPermissionMode = snapshot.lastNonPlanPermissionMode
    }
}
