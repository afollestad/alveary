import Foundation
import SwiftData

extension ConversationViewModel {
    func shouldAutoTrustWorkspace(
        _ workingDirectory: String,
        isAutomatedScheduledTurn: Bool = false
    ) -> Bool {
        guard let thread = dbThread() else {
            return false
        }
        switch thread.effectiveMode {
        case .project:
            return settingsService.current.autoTrustProjects
        case .task:
            guard thread.mode == .task else {
                return false
            }
        }
        if isAutomatedScheduledTurn {
            return isVerifiedOwnedAutomatedScheduledWorkspace(workingDirectory)
        }
        return isVerifiedPrivateTaskWorkspace(workingDirectory)
    }

    func isVerifiedPrivateTaskWorkspace(_ workingDirectory: String) -> Bool {
        guard let thread = dbThread(),
              thread.mode == .task,
              let descriptor = thread.taskWorkspaceDescriptor,
              descriptor.ownershipStrategy == .privateOwned,
              CanonicalPath.normalize(workingDirectory) == descriptor.primaryRoot else {
            return false
        }

        do {
            try taskWorkspaceOwnershipService.validateOwnedWorkspace(descriptor)
            return true
        } catch {
            return false
        }
    }

    func isVerifiedOwnedAutomatedScheduledWorkspace(_ workingDirectory: String) -> Bool {
        guard let thread = dbThread(),
              thread.mode == .task,
              let run = thread.scheduledTaskRun,
              let descriptor = thread.taskWorkspaceDescriptor,
              descriptor.ownershipStrategy == .privateOwned || descriptor.ownershipStrategy == .projectWorktreeOwned,
              CanonicalPath.normalize(workingDirectory) == descriptor.primaryRoot,
              descriptor.primaryRoot == run.preparedWorkspaceRoot,
              descriptor.ownershipStrategy == run.preparedWorkspaceOwnershipStrategy,
              descriptor.ownershipMarkerID == run.preparedWorkspaceMarkerID else {
            return false
        }

        do {
            try taskWorkspaceOwnershipService.validateOwnedWorkspace(descriptor)
            return true
        } catch {
            return false
        }
    }

    var canEditTaskWorkspaceConfiguration: Bool {
        taskWorkspaceConfigurationDisabledReason == nil
    }

    var taskWorkspaceConfigurationDisabledReason: String? {
        guard let thread = dbThread(), thread.resolvedWorkspaceDescriptor != nil else {
            return TaskWorkspaceGrantChangeError.notIdle.localizedDescription
        }
        if let definition = thread.blockingWorkspaceGrantScheduledTask {
            return SidebarViewModelError.scheduledTaskAttachment(definition.title).localizedDescription
        }
        if thread.hasBlockingScheduledTaskRunAttachment {
            return SidebarViewModelError.activeScheduledTaskRunAttachment.localizedDescription
        }
        guard thread.conversations.count == 1 else {
            return TaskWorkspaceGrantChangeError.multipleConversations.localizedDescription
        }
        guard !isUpdatingTaskWorkspaceConfiguration else {
            return TaskWorkspaceGrantChangeError.updateInProgress.localizedDescription
        }
        guard isTaskWorkspaceIdleForGrantChange else {
            return TaskWorkspaceGrantChangeError.notIdle.localizedDescription
        }
        return nil
    }

    func addTaskWorkspaceGrants(_ urls: [URL]) {
        guard !urls.isEmpty,
              let target = beginTaskWorkspaceGrantChange() else {
            return
        }
        let paths = urls.map(\.path)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { isUpdatingTaskWorkspaceConfiguration = false }
            await updateTaskWorkspaceGrants(.add(paths), target: target)
        }
    }

    func removeTaskWorkspaceGrant(_ path: String) {
        guard let target = beginTaskWorkspaceGrantChange() else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { isUpdatingTaskWorkspaceConfiguration = false }
            await updateTaskWorkspaceGrants(.remove(path), target: target)
        }
    }
}

private extension ConversationViewModel {
    var isTaskWorkspaceIdleForGrantChange: Bool {
        isTaskWorkspaceIdleForGrantChange(conversationID: conversation.id)
    }

    func isTaskWorkspaceIdleForGrantChange(conversationID: String) -> Bool {
        guard let thread = dbThread(),
              thread.workspaceSnapshot != nil,
              thread.blockingWorkspaceGrantScheduledTask == nil,
              !thread.hasBlockingScheduledTaskRunAttachment,
              thread.conversations.count == 1,
              canApplyPreStartupSettingChange,
              messageQueue.pending.isEmpty,
              state.pendingSessionSettingsChange == nil,
              !state.isExistingGoalControllerTurnActive,
              state.goalSnapshot?.status.isTerminal != false else {
            return false
        }

        switch agentsManager.status(for: conversationID) {
        case .busy, .waitingForUser:
            return false
        case .neutral, .idle, .stopped, .error:
            return true
        }
    }

    func beginTaskWorkspaceGrantChange() -> TaskWorkspaceGrantChangeTarget? {
        guard canEditTaskWorkspaceConfiguration, let target = taskWorkspaceGrantChangeTarget() else {
            state.lastTurnError = taskWorkspaceConfigurationDisabledReason ?? TaskWorkspaceGrantChangeError.notIdle.localizedDescription
            return nil
        }
        isUpdatingTaskWorkspaceConfiguration = true
        return target
    }

    func taskWorkspaceGrantChangeTarget() -> TaskWorkspaceGrantChangeTarget? {
        guard let conversation = dbConversation(), let thread = conversation.thread,
              let descriptor = thread.resolvedWorkspaceDescriptor, let workspace = thread.workspaceSnapshot else { return nil }
        return TaskWorkspaceGrantChangeTarget(
            conversationID: conversation.id, threadID: thread.persistentModelID,
            projectID: thread.project?.id, sectionID: thread.customSection?.id, workspace: workspace, descriptor: descriptor,
            isDraft: thread.isDraft, hasCompletedInitialSetup: thread.hasCompletedInitialSetup, useWorktree: thread.useWorktree
        )
    }

    func updateTaskWorkspaceGrants(_ mutation: TaskWorkspaceGrantMutation, target: TaskWorkspaceGrantChangeTarget) async {
        // A shared draft can move without changing its conversation or thread identity.
        guard !Task.isCancelled, taskWorkspaceGrantChangeTarget() == target else { return }
        let hasTrackedRuntime = await agentsManager.hasTrackedProcess(conversationId: target.conversationID)
        guard !Task.isCancelled, taskWorkspaceGrantChangeTarget() == target else { return }
        guard isTaskWorkspaceIdleForGrantChange(conversationID: target.conversationID) else {
            state.lastTurnError = TaskWorkspaceGrantChangeError.notIdle.localizedDescription
            return
        }
        let original = target.descriptor
        let originalSnapshot = target.workspace

        let updatedGrants: [String]
        do {
            updatedGrants = try taskWorkspaceGrants(after: mutation, original: original)
        } catch {
            state.lastTurnError = error.localizedDescription
            return
        }
        guard updatedGrants != original.grantedRoots else {
            return
        }

        let folders = await taskWorkspaceFolderSnapshots(paths: updatedGrants, original: originalSnapshot)
        await applyTaskWorkspaceGrants(folders, target: target, hasTrackedRuntime: hasTrackedRuntime)
    }

    func applyTaskWorkspaceGrants(
        _ folders: [SourceFolderSnapshot], target: TaskWorkspaceGrantChangeTarget, hasTrackedRuntime: Bool
    ) async {
        guard !Task.isCancelled, taskWorkspaceGrantChangeTarget() == target else { return }
        guard isTaskWorkspaceIdleForGrantChange(conversationID: target.conversationID),
              let liveThread = modelContext.resolveThread(id: target.threadID) else {
            state.lastTurnError = TaskWorkspaceGrantChangeError.notIdle.localizedDescription
            return
        }
        state.lastTurnError = nil
        defer { NotificationCenter.default.post(name: .workspaceConfigurationChanged, object: nil) }

        var rollbackTarget = target
        do {
            if modelContext.hasChanges { try modelContext.save() }
            try liveThread.replaceAdditionalFolders(folders)
            rollbackTarget = taskWorkspaceGrantChangeTarget() ?? target
            try modelContext.save()
            if liveThread.isDraft { liveThread.draftHasExplicitGrants = true }
            guard hasTrackedRuntime, target.hasCompletedInitialSetup else {
                return
            }

            let result = try await reconfigureSession(config: makeSpawnConfig(settingsSource: .nextTurn))
            guard result != .nextTurnRequired else {
                throw TaskWorkspaceGrantChangeError.runtimeReplacementDeferred
            }
        } catch {
            guard taskWorkspaceGrantChangeTarget() == rollbackTarget else { return }
            await rollbackTaskWorkspaceGrantChange(
                target: target,
                hasTrackedRuntime: hasTrackedRuntime,
                error: error
            )
        }
    }

    func taskWorkspaceFolderSnapshots(paths: [String], original: WorkspaceSnapshot) async -> [SourceFolderSnapshot] {
        var folders: [SourceFolderSnapshot] = []
        for path in paths {
            if let existing = original.grants.first(where: { $0.path == path }) {
                folders.append(existing)
            } else {
                folders.append(await resolveSourceFolder(path))
            }
        }
        return folders
    }

    func taskWorkspaceGrants(
        after mutation: TaskWorkspaceGrantMutation,
        original: TaskWorkspaceDescriptor
    ) throws -> [String] {
        let requestedGrants: [String]
        switch mutation {
        case .add(let paths):
            let canonicalAdditions = try taskWorkspaceOwnershipService.canonicalizeGrants(
                paths,
                excludingPrimaryRoot: original.primaryRoot
            )
            requestedGrants = original.grantedRoots + canonicalAdditions
        case .remove(let path):
            requestedGrants = original.grantedRoots.filter { $0 != path }
        }
        return TaskWorkspaceDescriptor(
            persistedPrimaryRoot: original.primaryRoot,
            persistedGrantedRoots: requestedGrants,
            ownershipStrategy: original.ownershipStrategy,
            ownershipMarkerID: original.ownershipMarkerID,
            persistedSourceProjectPath: original.sourceProjectPath
        ).grantedRoots
    }

    func rollbackTaskWorkspaceGrantChange(
        target: TaskWorkspaceGrantChangeTarget,
        hasTrackedRuntime: Bool,
        error: Error
    ) async {
        var rollbackFailures: [String] = []
        if let liveThread = modelContext.resolveThread(id: target.threadID) {
            if liveThread.mode == .task { liveThread.taskWorkspaceDescriptor = target.descriptor }
            liveThread.workspaceSnapshot = target.workspace
            do {
                try modelContext.save()
            } catch {
                rollbackFailures.append("saving the original folder access failed: \(error.localizedDescription)")
            }
        } else {
            rollbackFailures.append("the thread no longer exists")
        }

        if hasTrackedRuntime {
            do {
                let rollbackConfig = try makeSpawnConfig(settingsSource: .nextTurn)
                let result = try await reconfigureSession(config: rollbackConfig)
                if result == .nextTurnRequired {
                    rollbackFailures.append("restoring the current session was deferred")
                }
            } catch {
                rollbackFailures.append("restoring the current session failed: \(error.localizedDescription)")
            }
        }

        guard taskWorkspaceGrantChangeTarget() == target else { return }
        if rollbackFailures.isEmpty {
            state.lastTurnError = error.localizedDescription
        } else {
            state.lastTurnError = TaskWorkspaceGrantChangeError.rollbackFailed(
                original: error.localizedDescription,
                rollback: rollbackFailures.joined(separator: "; ")
            ).localizedDescription
        }
    }
}

private struct TaskWorkspaceGrantChangeTarget: Equatable {
    let conversationID: String
    let threadID: PersistentIdentifier
    let projectID: String?
    let sectionID: String?
    let workspace: WorkspaceSnapshot
    let descriptor: TaskWorkspaceDescriptor
    let isDraft: Bool
    let hasCompletedInitialSetup: Bool
    let useWorktree: Bool
}

private enum TaskWorkspaceGrantMutation {
    case add([String])
    case remove(String)
}

private enum TaskWorkspaceGrantChangeError: LocalizedError {
    case multipleConversations
    case notIdle
    case rollbackFailed(original: String, rollback: String)
    case runtimeReplacementDeferred
    case updateInProgress

    var errorDescription: String? {
        switch self {
        case .multipleConversations:
            "Folder access can only be changed while the thread has one conversation."
        case .notIdle:
            "Wait for the thread to become fully idle before changing folder access."
        case let .rollbackFailed(original, rollback):
            "Folder access could not be applied (\(original)), and rollback was incomplete: \(rollback)."
        case .runtimeReplacementDeferred:
            "Folder access could not be applied to the current session. Try again when the thread is idle."
        case .updateInProgress:
            "Folder access is still being applied."
        }
    }
}
