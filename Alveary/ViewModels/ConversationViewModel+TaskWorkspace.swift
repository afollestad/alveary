import Foundation
import SwiftData

extension ConversationViewModel {
    func shouldAutoTrustWorkspace(_ workingDirectory: String) -> Bool {
        guard dbThread()?.mode == .task else {
            return settingsService.current.autoTrustProjects
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

    var canEditTaskWorkspaceConfiguration: Bool {
        taskWorkspaceConfigurationDisabledReason == nil
    }

    var taskWorkspaceConfigurationDisabledReason: String? {
        guard let thread = dbThread(), thread.mode == .task else {
            return TaskWorkspaceGrantChangeError.notIdle.localizedDescription
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
              beginTaskWorkspaceGrantChange() else {
            return
        }
        let conversationID = conversation.id
        let paths = urls.map(\.path)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { isUpdatingTaskWorkspaceConfiguration = false }
            guard dbThread()?.taskWorkspaceDescriptor != nil else {
                state.lastTurnError = TaskWorkspaceGrantChangeError.notIdle.localizedDescription
                return
            }
            await updateTaskWorkspaceGrants(.add(paths), conversationID: conversationID)
        }
    }

    func removeTaskWorkspaceGrant(_ path: String) {
        guard beginTaskWorkspaceGrantChange() else {
            return
        }
        let conversationID = conversation.id
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { isUpdatingTaskWorkspaceConfiguration = false }
            guard dbThread()?.taskWorkspaceDescriptor != nil else {
                state.lastTurnError = TaskWorkspaceGrantChangeError.notIdle.localizedDescription
                return
            }
            await updateTaskWorkspaceGrants(.remove(path), conversationID: conversationID)
        }
    }
}

private extension ConversationViewModel {
    var isTaskWorkspaceIdleForGrantChange: Bool {
        isTaskWorkspaceIdleForGrantChange(conversationID: conversation.id)
    }

    func isTaskWorkspaceIdleForGrantChange(conversationID: String) -> Bool {
        guard let thread = dbThread(),
              thread.mode == .task,
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

    func beginTaskWorkspaceGrantChange() -> Bool {
        guard canEditTaskWorkspaceConfiguration else {
            state.lastTurnError = taskWorkspaceConfigurationDisabledReason
            return false
        }
        isUpdatingTaskWorkspaceConfiguration = true
        return true
    }

    func updateTaskWorkspaceGrants(_ mutation: TaskWorkspaceGrantMutation, conversationID: String) async {
        let hasTrackedRuntime = await agentsManager.hasTrackedProcess(conversationId: conversationID)
        guard isTaskWorkspaceIdleForGrantChange(conversationID: conversationID),
              let thread = dbThread(),
              let original = thread.taskWorkspaceDescriptor else {
            state.lastTurnError = TaskWorkspaceGrantChangeError.notIdle.localizedDescription
            return
        }

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

        let updated = TaskWorkspaceDescriptor(
            primaryRoot: original.primaryRoot,
            grantedRoots: updatedGrants,
            ownershipStrategy: original.ownershipStrategy,
            ownershipMarkerID: original.ownershipMarkerID,
            sourceProjectPath: original.sourceProjectPath
        )
        let threadID = thread.persistentModelID
        let hasCompletedInitialSetup = thread.hasCompletedInitialSetup
        thread.taskWorkspaceDescriptor = updated
        state.lastTurnError = nil

        do {
            try modelContext.save()
            guard hasTrackedRuntime, hasCompletedInitialSetup else {
                return
            }

            let result = try await reconfigureSession(config: makeSpawnConfig(settingsSource: .nextTurn))
            guard result != .nextTurnRequired else {
                throw TaskWorkspaceGrantChangeError.runtimeReplacementDeferred
            }
        } catch {
            await rollbackTaskWorkspaceGrantChange(
                original: original,
                threadID: threadID,
                hasTrackedRuntime: hasTrackedRuntime,
                error: error
            )
        }
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
            let canonicalPath = CanonicalPath.normalize(path)
            requestedGrants = original.grantedRoots.filter { CanonicalPath.normalize($0) != canonicalPath }
        }
        return TaskWorkspaceDescriptor(
            primaryRoot: original.primaryRoot,
            grantedRoots: requestedGrants,
            ownershipStrategy: original.ownershipStrategy,
            ownershipMarkerID: original.ownershipMarkerID,
            sourceProjectPath: original.sourceProjectPath
        ).grantedRoots
    }

    func rollbackTaskWorkspaceGrantChange(
        original: TaskWorkspaceDescriptor,
        threadID: PersistentIdentifier,
        hasTrackedRuntime: Bool,
        error: Error
    ) async {
        var rollbackFailures: [String] = []
        if let liveThread = modelContext.resolveThread(id: threadID) {
            liveThread.taskWorkspaceDescriptor = original
            do {
                try modelContext.save()
            } catch {
                rollbackFailures.append("saving the original folder access failed: \(error.localizedDescription)")
            }
        } else {
            rollbackFailures.append("the task no longer exists")
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
            "Folder access can only be changed while the task has one conversation."
        case .notIdle:
            "Wait for the task to become fully idle before changing folder access."
        case let .rollbackFailed(original, rollback):
            "Folder access could not be applied (\(original)), and rollback was incomplete: \(rollback)."
        case .runtimeReplacementDeferred:
            "Folder access could not be applied to the current session. Try again when the task is idle."
        case .updateInProgress:
            "Task folder access is still being applied."
        }
    }
}
