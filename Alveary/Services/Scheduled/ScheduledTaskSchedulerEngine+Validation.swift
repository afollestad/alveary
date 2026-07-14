import Foundation

@MainActor
extension ScheduledTaskSchedulerEngine {
    func isCurrent(
        _ request: ScheduledTaskRunNowRequest,
        for definition: ScheduledTask
    ) -> Bool {
        ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: request.triggeredAt,
            recurrenceCalculator: recurrenceCalculator,
            idempotencyKey: request.idempotencyKey
        ) == request
    }

    func projectConfigurationSnapshot(
        for definition: ScheduledTask
    ) -> ScheduledProjectConfigSnapshot? {
        definition.project.map { project in
            ScheduledProjectConfigSnapshot(
                path: project.path,
                baseRef: project.baseRef,
                remoteName: project.remoteName
            )
        }
    }

    func invalidDefinitionReason(
        _ recurrence: ScheduledTaskRecurrence,
        definition: ScheduledTask
    ) -> String? {
        guard ScheduledTaskState(rawValue: definition.stateRawValue) != nil else {
            return "Scheduled task state is invalid."
        }
        do {
            try recurrenceCalculator.validate(
                recurrence,
                timeZoneIdentifier: definition.timeZoneIdentifier
            )
        } catch {
            return error.localizedDescription
        }
        guard ScheduledTaskWorkspaceKind(rawValue: definition.workspaceKindRawValue) != nil else {
            return "Scheduled task workspace kind is invalid."
        }
        guard ScheduledTaskWorkspaceStrategy(rawValue: definition.workspaceStrategyRawValue) != nil else {
            return "Scheduled task workspace strategy is invalid."
        }
        if definition.state == .active,
           definition.nextOccurrenceAt == nil,
           definition.pendingOccurrenceAt == nil {
            return "Scheduled task next occurrence is missing."
        }
        return nil
    }
}
