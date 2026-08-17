import Foundation

extension ScheduledTaskSchedulerEngine {
    func validatePreflight(_ snapshot: ScheduledTaskPreflightSnapshot) async -> ScheduledTaskPreflightOutcome {
        if let gatedConversationID = snapshot.gatedConversationID,
           !targetIsAvailableForClaim(conversationID: gatedConversationID) {
            return .targetBusy
        }
        let outcome = await preflightValidator(snapshot)
        if case .ready = outcome,
           let gatedConversationID = snapshot.gatedConversationID,
           !targetIsAvailableForClaim(conversationID: gatedConversationID) {
            return .targetBusy
        }
        return outcome
    }

    func targetIsAvailableForClaim(conversationID: String) -> Bool {
        guard targetIsReady(conversationID) else {
            return false
        }
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
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
