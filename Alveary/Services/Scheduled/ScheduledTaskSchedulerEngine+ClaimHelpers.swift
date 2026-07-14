import Foundation

@MainActor
extension ScheduledTaskSchedulerEngine {
    func makePreflightSnapshot(
        definition: ScheduledTask,
        recurrence: ScheduledTaskRecurrence,
        occurrenceAt: Date
    ) -> ScheduledTaskPreflightSnapshot {
        ScheduledTaskPreflightSnapshot(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            scheduledOccurrenceAt: occurrenceAt,
            recurrence: recurrence,
            timeZoneIdentifier: definition.timeZoneIdentifier,
            providerID: definition.providerID,
            model: definition.model,
            effort: definition.effort,
            permissionMode: definition.permissionMode,
            workspaceKind: definition.workspaceKind,
            workspaceStrategy: definition.workspaceStrategy,
            projectPath: definition.project?.path,
            projectBaseRef: definition.project?.baseRef,
            projectRemoteName: definition.project?.remoteName,
            grantedRoots: definition.grantedRoots
        )
    }

    func runNowOccurrenceID(_ request: ScheduledTaskRunNowRequest) -> String {
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
