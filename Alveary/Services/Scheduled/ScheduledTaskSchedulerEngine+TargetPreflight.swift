import Foundation

extension ScheduledTaskSchedulerEngine {
    func validatePreflight(_ snapshot: ScheduledTaskPreflightSnapshot) async -> ScheduledTaskPreflightOutcome {
        if let target = snapshot.target,
           !targetIsAvailableForClaim(target) {
            return .targetBusy
        }
        let outcome = await preflightValidator(snapshot)
        if case .ready = outcome,
           let target = snapshot.target,
           !targetIsAvailableForClaim(target) {
            return .targetBusy
        }
        return outcome
    }

    func targetIsAvailableForClaim(_ target: ScheduledTaskTargetSnapshot) -> Bool {
        guard targetIsReady(target.conversationID) else {
            return false
        }
        guard let conversation = modelContext.resolveConversation(conversationID: target.conversationID),
              conversation.isMain,
              let thread = conversation.thread else {
            return true
        }
        return !thread.hasBlockingScheduledTaskRunAttachment &&
            !ScheduledTaskExistingTargetReadiness.hasBlockingPersistedInteraction(in: conversation)
    }
}

extension ScheduledTaskWorkspaceIdentitySnapshot {
    @MainActor
    func matchesConfiguration(
        _ target: ScheduledTaskTargetSnapshot?,
        definition: ScheduledTask
    ) -> Bool {
        matchesConfiguration(
            workspaceKind: target?.workspaceKind ?? definition.workspaceKind,
            projectPath: target?.projectPath ?? definition.project?.path,
            grantedRootPaths: target?.grantedRoots ?? definition.grantedRoots
        )
    }
}
