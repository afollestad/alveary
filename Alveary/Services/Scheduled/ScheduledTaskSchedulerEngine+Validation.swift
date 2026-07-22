import Foundation

@MainActor
extension ScheduledTaskSchedulerEngine {
    func applyRunNowConsumption(
        _ request: ScheduledTaskRunNowRequest,
        to definition: ScheduledTask
    ) throws {
        guard request.consumesScheduledOccurrence else { return }
        if let pendingOccurrenceAt = definition.pendingOccurrenceAt,
           pendingOccurrenceAt <= request.triggeredAt {
            definition.pendingOccurrenceAt = nil
            definition.targetWaitStartedAt = nil
        }
        if let recurrence = definition.recurrence {
            definition.nextOccurrenceAt = try recurrenceCalculator.nextOccurrence(
                strictlyAfter: request.triggeredAt,
                recurrence: recurrence,
                timeZoneIdentifier: definition.timeZoneIdentifier
            )
            if recurrence.isOneShot {
                definition.state = .completed
                definition.nextOccurrenceAt = nil
            }
        }
    }

    func pauseInvalidDefinition(
        _ definition: ScheduledTask,
        reason: String,
        at actionDate: Date
    ) throws -> ScheduledTaskClaimResult {
        let definitionSnapshot = ScheduledTaskPauseSnapshot(definition)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReason = trimmedReason.isEmpty ? "Scheduled task preflight failed." : trimmedReason
        let nextOccurrence = definition.recurrence.flatMap { recurrence in
            try? recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: recurrence,
                timeZoneIdentifier: definition.timeZoneIdentifier
            )
        }
        definition.state = .paused
        definition.nextOccurrenceAt = nextOccurrence
        definition.pendingOccurrenceAt = nil
        definition.targetWaitStartedAt = nil
        definition.pauseReason = resolvedReason
        definition.lastError = resolvedReason
        definition.revision += 1
        definition.modifiedAt = actionDate
        try persistInvalidDefinitionPause(definition: definition, restoring: definitionSnapshot)
        return .paused(reason: resolvedReason)
    }

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
        guard let destination = definition.decodedDestination else {
            return "Scheduled task destination is invalid."
        }
        if destination == .existingThread,
           targetSnapshot(for: definition) == nil {
            return "The pinned thread selected for this schedule is no longer available."
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
