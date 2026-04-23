import Foundation
import SwiftData

extension ConversationViewModel {
    // Reject dropdown changes while the agent is working or waiting on approval. The composer pickers
    // are already `.disabled` in busy modes, but gate at the view-model entry
    // point too so any stray binding write (programmatic, race on mode flip)
    // can't silently persist to the DB or fork the session mid-turn or mid-approval.
    var canApplySettingsChange: Bool {
        !state.turnState.isActive && !state.isSendingMessage && state.pendingToolApproval == nil
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

    @discardableResult
    func applyModelChange(_ newValue: String) -> Task<Void, Never> {
        guard canApplySettingsChange else { return .noop }
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.resolveThread(id: threadID) else {
            return .noop
        }

        let previousValue = dbThread.model ?? AppSettings.defaultModelValue
        guard previousValue != newValue else { return .noop }

        dbThread.model = newValue == AppSettings.defaultModelValue ? nil : newValue

        // Model-specific efforts (e.g. `xhigh` for Opus 4.7) must fall back when
        // switching to a model that does not support them; otherwise the CLI
        // would reject the flag on the next spawn. The fallback uses the new
        // model's preferred default so switching back into Opus lands on
        // `xhigh` rather than the universal `medium`.
        let previousEffort = dbThread.effort
        if !AppSettings.effortLevel(previousEffort, isSupportedByModel: newValue) {
            dbThread.effort = AppSettings.defaultEffortLevel(forModel: newValue)
        }

        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.model = previousValue == AppSettings.defaultModelValue ? nil : previousValue
            dbThread.effort = previousEffort
            state.lastTurnError = error.localizedDescription
            return .noop
        }

        guard shouldReconfigureOnSettingChange() else { return .noop }

        return Task { @MainActor [self] in
            do {
                try await reconfigureSession()
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

        dbThread.effort = newValue
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.effort = previousValue
            state.lastTurnError = error.localizedDescription
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

        let previousBannerVisibility = state.showPermissionBanner
        let previousDeniedTools = state.lastPermissionDeniedToolNames

        dbThread.permissionMode = newValue
        state.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.permissionMode = previousValue
            state.lastTurnError = error.localizedDescription
            return .noop
        }

        guard shouldReconfigureOnSettingChange() else { return .noop }

        return Task { @MainActor [self] in
            do {
                try await reconfigureSession()
            } catch {
                dbThread.permissionMode = previousValue
                try? modelContext.save()
                state.showPermissionBanner = previousBannerVisibility
                state.lastPermissionDeniedToolNames = previousDeniedTools
                state.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyWorktreePreferenceChange(_ newValue: Bool) {
        guard canApplySettingsChange else { return }
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

private extension Task where Success == Void, Failure == Never {
    static var noop: Task<Void, Never> { Task {} }
}
