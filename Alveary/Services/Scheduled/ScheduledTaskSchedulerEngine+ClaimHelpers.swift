import Foundation

@MainActor
extension ScheduledTaskSchedulerEngine {
    func makePreflightSnapshot(
        definition: ScheduledTask,
        recurrence: ScheduledTaskRecurrence,
        occurrenceAt: Date
    ) -> ScheduledTaskPreflightSnapshot {
        guard let destination = definition.decodedDestination else {
            preconditionFailure("Scheduled task destination must be validated before preflight")
        }
        let target = targetSnapshot(for: definition)
        return ScheduledTaskPreflightSnapshot(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            scheduledOccurrenceAt: occurrenceAt,
            recurrence: recurrence,
            timeZoneIdentifier: definition.timeZoneIdentifier,
            providerID: target?.providerID ?? definition.providerID,
            model: target == nil ? definition.model : target?.model,
            effort: target?.effort ?? definition.effort,
            permissionMode: target?.permissionMode ?? definition.permissionMode,
            workspaceKind: target?.workspaceKind ?? definition.workspaceKind,
            workspaceStrategy: target?.workspaceStrategy ?? definition.workspaceStrategy,
            projectPath: target?.projectPath ?? definition.project?.path,
            projectBaseRef: definition.project?.baseRef,
            projectRemoteName: definition.project?.remoteName,
            grantedRoots: target?.grantedRoots ?? definition.grantedRoots,
            destination: destination,
            target: target
        )
    }

    func targetSnapshot(for definition: ScheduledTask) -> ScheduledTaskTargetSnapshot? {
        guard definition.decodedDestination == .existingThread,
              let thread = definition.targetThread,
              thread.isPinned,
              thread.archivedAt == nil,
              !thread.isDraft,
              !thread.hasPendingScheduledTaskWorktreeCleanup else {
            return nil
        }
        let mainConversations = thread.conversations.filter(\.isMain)
        guard mainConversations.count == 1,
              let conversation = mainConversations.first else {
            return nil
        }

        let workspace: ScheduledTaskTargetWorkspace
        switch thread.effectiveMode {
        case .project:
            workspace = ScheduledTaskTargetWorkspace(
                projectPath: thread.primaryWorkingDirectory,
                grantedRoots: thread.taskGrantedRoots
            )
        case .task:
            guard let descriptor = thread.taskWorkspaceDescriptor else {
                return nil
            }
            workspace = ScheduledTaskTargetWorkspace(
                projectPath: descriptor.primaryRoot,
                grantedRoots: descriptor.grantedRoots
            )
        }
        return ScheduledTaskTargetSnapshot(
            conversationID: conversation.id,
            threadName: thread.name,
            providerID: conversation.provider ?? definition.providerID,
            model: thread.model,
            effort: thread.effort,
            permissionMode: thread.permissionMode,
            planModeEnabled: thread.planModeEnabled ?? false,
            speedMode: thread.normalizedSpeedMode.rawValue,
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: workspace.projectPath,
            grantedRoots: workspace.grantedRoots
        )
    }

    func runNowOccurrenceID(_ request: ScheduledTaskRunNowRequest) -> String {
        if let idempotencyKey = request.idempotencyKey,
           !idempotencyKey.isEmpty {
            return "run-now:\(request.definitionID):idempotent:\(idempotencyKey)"
        }
        if request.consumesScheduledOccurrence {
            return scheduledOccurrenceID(
                definitionID: request.definitionID,
                occurrenceAt: request.occurrenceAt
            )
        }
        let instantBits = request.occurrenceAt.timeIntervalSinceReferenceDate.bitPattern
        return "run-now:\(request.definitionID):\(String(instantBits, radix: 16))"
    }

    func hasActiveRun(_ definition: ScheduledTask) -> Bool {
        definition.runs.contains { !$0.hasKnownTerminalStatus }
    }

    func scheduledOccurrenceID(
        definitionID: String,
        occurrenceAt: Date
    ) -> String {
        let instantBits = occurrenceAt.timeIntervalSinceReferenceDate.bitPattern
        return "scheduled:\(definitionID):\(String(instantBits, radix: 16))"
    }
}

private struct ScheduledTaskTargetWorkspace {
    let projectPath: String?
    let grantedRoots: [String]
}
