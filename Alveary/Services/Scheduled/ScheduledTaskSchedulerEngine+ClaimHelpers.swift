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
            harnessID: target?.harnessID ?? definition.harnessID,
            model: target == nil ? definition.model : target?.model,
            effort: target?.effort ?? definition.effort,
            permissionMode: target?.permissionMode ?? definition.permissionMode,
            workspaceKind: target?.workspaceKind ?? definition.workspaceKind,
            workspaceStrategy: target?.workspaceStrategy ?? definition.workspaceStrategy,
            projectPath: target == nil ? definition.workspaceSnapshot?.primarySource?.path : target?.projectPath,
            projectBaseRef: definition.workspaceSnapshot?.primarySource?.baseRef,
            projectRemoteName: definition.workspaceSnapshot?.primarySource?.remoteName,
            grantedRoots: target?.grantedRoots ?? definition.workspaceSnapshot?.grants.map(\.path) ?? [],
            destination: destination,
            target: target,
            reusedTarget: reusedTarget(for: definition)
        )
    }

    /// The healthy thread a `.reusedThread` schedule should post into, or nil when the next run
    /// must mint a fresh one. `AgentThread.isHealthyReusedScheduledTaskTarget` owns what healthy
    /// means, because the Scheduled card and editor name that same thread.
    func reusedTarget(for definition: ScheduledTask) -> ScheduledTaskReusedTarget? {
        guard definition.decodedDestination == .reusedThread,
              let thread = definition.reusedThread,
              thread.isHealthyReusedScheduledTaskTarget,
              let conversation = thread.soleMainConversation else {
            return nil
        }
        return ScheduledTaskReusedTarget(
            conversationID: conversation.id,
            threadName: thread.name,
            threadID: thread.persistentModelID,
            harnessDiscoveryDirectory: definition.harnessID == "opencode" ? thread.primaryWorkingDirectory : nil
        )
    }

    /// The conversation whose availability gates claiming for this definition, mirroring
    /// `ScheduledTaskPreflightSnapshot.gatedConversationID` for the synchronous rechecks.
    func gatedConversationID(for definition: ScheduledTask) -> String? {
        targetSnapshot(for: definition)?.conversationID ?? reusedTarget(for: definition)?.conversationID
    }

    func targetSnapshot(for definition: ScheduledTask) -> ScheduledTaskTargetSnapshot? {
        guard definition.decodedDestination == .existingThread,
              let thread = definition.targetThread,
              thread.archivedAt == nil,
              !thread.isDraft,
              !thread.hasPendingScheduledTaskWorktreeCleanup else {
            return nil
        }
        guard let conversation = definition.resolvedTargetConversation else {
            return nil
        }

        guard let descriptor = thread.resolvedWorkspaceDescriptor,
              let snapshot = thread.workspaceSnapshot else { return nil }
        return ScheduledTaskTargetSnapshot(
            conversationID: conversation.id,
            threadName: thread.name,
            harnessID: conversation.harness ?? definition.harnessID,
            model: thread.model,
            effort: thread.effort,
            permissionMode: thread.permissionMode,
            planModeEnabled: thread.planModeEnabled ?? false,
            speedMode: thread.normalizedSpeedMode.rawValue,
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: descriptor.primaryRoot,
            grantedRoots: snapshot.grants.map(\.path),
            workspaceSnapshot: snapshot
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
