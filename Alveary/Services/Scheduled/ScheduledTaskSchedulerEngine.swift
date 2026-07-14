import Foundation
import SwiftData

@MainActor
final class ScheduledTaskSchedulerEngine {
    typealias StateSaver = @MainActor (ModelContext) throws -> Void

    let modelContext: ModelContext
    let recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    private let preflightValidator: ScheduledTaskPreflightValidator
    let saveState: StateSaver

    init(
        modelContext: ModelContext,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        preflightValidator: @escaping ScheduledTaskPreflightValidator,
        saveState: @escaping StateSaver = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.recurrenceCalculator = recurrenceCalculator
        self.preflightValidator = preflightValidator
        self.saveState = saveState
    }

    /// Claims the latest due occurrence after validation. The definition is re-resolved
    /// after the asynchronous preflight so an edit or pause cannot be overwritten.
    func claimDue(
        definitionID: String,
        at actionDate: Date = .now
    ) async throws -> ScheduledTaskClaimResult {
        switch try prepareClaim(definitionID: definitionID, at: actionDate) {
        case let .resolved(result):
            return result
        case let .requiresPreflight(snapshot, recheck):
            let preflightOutcome = await preflightValidator(snapshot)
            try Task.checkCancellation()
            return try finishClaim(
                definitionID: definitionID,
                recheck: recheck,
                preflightOutcome: preflightOutcome,
                at: actionDate
            )
        }
    }

    func claimRunNow(
        _ request: ScheduledTaskRunNowRequest
    ) async throws -> ScheduledTaskClaimResult {
        try savePendingChanges()
        if let idempotencyKey = request.idempotencyKey,
           !idempotencyKey.isEmpty,
           let existingRun = resolveRun(occurrenceID: runNowOccurrenceID(request)) {
            // The original claim persisted its run and cadence mutation atomically. A replay must
            // not revalidate changed external state or consume a later scheduled occurrence.
            return .alreadyClaimed(runID: existingRun.persistentModelID)
        }
        guard let definition = modelContext.resolveScheduledTask(id: request.definitionID) else {
            return .definitionNotFound
        }
        guard definition.revision == request.definitionRevision,
              isCurrent(request, for: definition)
        else {
            return .changedDuringPreflight
        }
        guard !hasActiveRun(definition) else {
            return .activeRunExists
        }
        guard let recurrence = definition.recurrence else {
            return try pauseInvalidDefinition(
                definition,
                reason: "Scheduled task recurrence is invalid.",
                at: request.triggeredAt
            )
        }
        if let invalidReason = invalidDefinitionReason(recurrence, definition: definition) {
            return try pauseInvalidDefinition(
                definition,
                reason: invalidReason,
                at: request.triggeredAt
            )
        }

        let snapshot = makePreflightSnapshot(
            definition: definition,
            recurrence: recurrence,
            occurrenceAt: request.occurrenceAt
        )
        let recheck = ScheduledTaskRunNowRecheck(
            definitionRevision: definition.revision,
            expectedState: definition.state,
            expectedNextOccurrenceAt: definition.nextOccurrenceAt,
            expectedPendingOccurrenceAt: definition.pendingOccurrenceAt,
            expectedProjectConfiguration: projectConfigurationSnapshot(for: definition)
        )
        let outcome = await preflightValidator(snapshot)
        try Task.checkCancellation()
        return try finishRunNowClaim(request, recheck: recheck, preflightOutcome: outcome)
    }
}

private extension ScheduledTaskSchedulerEngine {
    enum ClaimPreparation {
        case resolved(ScheduledTaskClaimResult)
        case requiresPreflight(ScheduledTaskPreflightSnapshot, ScheduledTaskClaimRecheck)
    }

    struct DuePlan {
        let occurrenceAt: Date
        let nextOccurrenceAt: Date?
        let consumesNextOccurrence: Bool
        let consumesPendingOccurrence: Bool
        let isOutsideCatchUpWindow: Bool
    }

    func prepareClaim(
        definitionID: String,
        at actionDate: Date
    ) throws -> ClaimPreparation {
        try savePendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            return .resolved(.definitionNotFound)
        }
        guard definition.state != .completed else {
            return .resolved(.inactive)
        }
        guard let recurrence = definition.recurrence else {
            return .resolved(try pauseInvalidDefinition(definition, reason: "Scheduled task recurrence is invalid.", at: actionDate))
        }
        if let invalidReason = invalidDefinitionReason(recurrence, definition: definition) {
            return .resolved(try pauseInvalidDefinition(definition, reason: invalidReason, at: actionDate))
        }
        guard let duePlan = try makeDuePlan(
            definition: definition,
            recurrence: recurrence,
            through: actionDate
        ) else {
            return .resolved(definition.state == .active ? .notDue : .inactive)
        }

        if definition.state == .paused {
            return .resolved(try skip(duePlan: duePlan, definition: definition, at: actionDate))
        }
        guard definition.state == .active else {
            return .resolved(.inactive)
        }
        if hasActiveRun(definition) {
            return .resolved(try recordOverlap(duePlan: duePlan, definition: definition))
        }
        if duePlan.isOutsideCatchUpWindow {
            return .resolved(try skip(duePlan: duePlan, definition: definition, at: actionDate))
        }

        let snapshot = makePreflightSnapshot(
            definition: definition,
            recurrence: recurrence,
            occurrenceAt: duePlan.occurrenceAt
        )
        let recheck = ScheduledTaskClaimRecheck(
            definitionRevision: definition.revision,
            expectedNextOccurrenceAt: definition.nextOccurrenceAt,
            expectedPendingOccurrenceAt: definition.pendingOccurrenceAt,
            expectedProjectConfiguration: projectConfigurationSnapshot(for: definition),
            occurrenceAt: duePlan.occurrenceAt
        )
        return .requiresPreflight(snapshot, recheck)
    }

    func finishClaim(
        definitionID: String,
        recheck: ScheduledTaskClaimRecheck,
        preflightOutcome: ScheduledTaskPreflightOutcome,
        at actionDate: Date
    ) throws -> ScheduledTaskClaimResult {
        guard let currentDefinition = modelContext.resolveScheduledTask(id: definitionID) else {
            return .definitionNotFound
        }
        guard currentDefinition.state == .active,
              currentDefinition.revision == recheck.definitionRevision,
              currentDefinition.nextOccurrenceAt == recheck.expectedNextOccurrenceAt,
              currentDefinition.pendingOccurrenceAt == recheck.expectedPendingOccurrenceAt,
              projectConfigurationSnapshot(for: currentDefinition) == recheck.expectedProjectConfiguration,
              let currentRecurrence = currentDefinition.recurrence,
              let currentDuePlan = try makeDuePlan(
                  definition: currentDefinition,
                  recurrence: currentRecurrence,
                  through: actionDate
              ),
              currentDuePlan.occurrenceAt == recheck.occurrenceAt
        else {
            return .changedDuringPreflight
        }
        guard !hasActiveRun(currentDefinition) else {
            return try recordOverlap(duePlan: currentDuePlan, definition: currentDefinition)
        }

        switch preflightOutcome {
        case .ready(let workspaceIdentities):
            guard workspaceIdentities.matchesConfiguration(
                workspaceKind: currentDefinition.workspaceKind,
                projectPath: currentDefinition.project?.path,
                grantedRootPaths: currentDefinition.grantedRoots
            ) else {
                return .changedDuringPreflight
            }
            return try claim(
                duePlan: currentDuePlan,
                definition: currentDefinition,
                workspaceIdentities: workspaceIdentities,
                at: actionDate
            )
        case let .invalid(reason):
            return try pauseInvalidDefinition(currentDefinition, reason: reason, at: actionDate)
        }
    }

    func finishRunNowClaim(
        _ request: ScheduledTaskRunNowRequest,
        recheck: ScheduledTaskRunNowRecheck,
        preflightOutcome: ScheduledTaskPreflightOutcome
    ) throws -> ScheduledTaskClaimResult {
        guard let definition = modelContext.resolveScheduledTask(id: request.definitionID) else {
            return .definitionNotFound
        }
        guard definition.revision == recheck.definitionRevision,
              definition.state == recheck.expectedState,
              definition.nextOccurrenceAt == recheck.expectedNextOccurrenceAt,
              definition.pendingOccurrenceAt == recheck.expectedPendingOccurrenceAt,
              projectConfigurationSnapshot(for: definition) == recheck.expectedProjectConfiguration,
              isCurrent(request, for: definition)
        else {
            return .changedDuringPreflight
        }
        guard !hasActiveRun(definition) else {
            return .activeRunExists
        }

        switch preflightOutcome {
        case .ready(let workspaceIdentities):
            guard workspaceIdentities.matchesConfiguration(
                workspaceKind: definition.workspaceKind,
                projectPath: definition.project?.path,
                grantedRootPaths: definition.grantedRoots
            ) else {
                return .changedDuringPreflight
            }
            return try persistRunNowClaim(
                request,
                definition: definition,
                workspaceIdentities: workspaceIdentities
            )
        case let .invalid(reason):
            return try pauseInvalidDefinition(definition, reason: reason, at: request.triggeredAt)
        }
    }

    func makeDuePlan(
        definition: ScheduledTask,
        recurrence: ScheduledTaskRecurrence,
        through actionDate: Date
    ) throws -> DuePlan? {
        let pendingDue = definition.pendingOccurrenceAt.flatMap { occurrence in
            occurrence <= actionDate ? occurrence : nil
        }
        var latestNextDue: Date?
        var nextOccurrenceAt = definition.nextOccurrenceAt
        if let persistedNext = definition.nextOccurrenceAt, persistedNext <= actionDate {
            let window = try recurrenceCalculator.coalescedOccurrences(
                startingAt: persistedNext,
                through: actionDate,
                recurrence: recurrence,
                timeZoneIdentifier: definition.timeZoneIdentifier
            )
            latestNextDue = window.latestDueOccurrence
            nextOccurrenceAt = window.nextOccurrence
        }

        guard let occurrenceAt = ScheduledTaskRecurrenceCalculator.latestCoalescedOccurrence(
            existing: pendingDue,
            candidate: latestNextDue
        ) else {
            return nil
        }
        return DuePlan(
            occurrenceAt: occurrenceAt,
            nextOccurrenceAt: nextOccurrenceAt,
            consumesNextOccurrence: latestNextDue != nil,
            consumesPendingOccurrence: pendingDue != nil,
            isOutsideCatchUpWindow: actionDate.timeIntervalSince(occurrenceAt) > ScheduledTaskRecurrenceCalculator.defaultCatchUpAge
        )
    }

    func claim(
        duePlan: DuePlan,
        definition: ScheduledTask,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot,
        at actionDate: Date
    ) throws -> ScheduledTaskClaimResult {
        if duePlan.isOutsideCatchUpWindow {
            return try skip(
                duePlan: duePlan,
                definition: definition,
                workspaceIdentities: workspaceIdentities,
                at: actionDate
            )
        }

        let occurrenceID = scheduledOccurrenceID(
            definitionID: definition.id,
            occurrenceAt: duePlan.occurrenceAt
        )
        if let existingRun = resolveRun(occurrenceID: occurrenceID) {
            let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
            applyConsumedOccurrences(duePlan, to: definition)
            try persistClaimMutation(
                definition: definition,
                restoring: definitionSnapshot
            )
            return .alreadyClaimed(runID: existingRun.persistentModelID)
        }

        let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: occurrenceID,
            occurrenceAt: duePlan.occurrenceAt,
            triggeredAt: actionDate,
            triggerKind: .scheduled,
            workspaceIdentitySnapshot: workspaceIdentities
        )
        applyConsumedOccurrences(duePlan, to: definition)
        modelContext.insert(run)
        try persistClaimMutation(
            definition: definition,
            restoring: definitionSnapshot,
            insertedRun: run
        )
        return .claimed(runID: run.persistentModelID)
    }

    func skip(
        duePlan: DuePlan,
        definition: ScheduledTask,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot? = nil,
        at actionDate: Date
    ) throws -> ScheduledTaskClaimResult {
        let occurrenceID = scheduledOccurrenceID(
            definitionID: definition.id,
            occurrenceAt: duePlan.occurrenceAt
        )
        if let existingRun = resolveRun(occurrenceID: occurrenceID) {
            let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
            applyConsumedOccurrences(duePlan, to: definition)
            try persistClaimMutation(
                definition: definition,
                restoring: definitionSnapshot
            )
            return .alreadyClaimed(runID: existingRun.persistentModelID)
        }

        let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: occurrenceID,
            occurrenceAt: duePlan.occurrenceAt,
            triggeredAt: actionDate,
            triggerKind: .scheduled,
            status: .skipped,
            workspaceIdentitySnapshot: workspaceIdentities
        )
        run.finishedAt = actionDate
        applyConsumedOccurrences(duePlan, to: definition)
        modelContext.insert(run)
        try persistClaimMutation(
            definition: definition,
            restoring: definitionSnapshot,
            insertedRun: run
        )
        return .skipped(runID: run.persistentModelID)
    }

    func recordOverlap(
        duePlan: DuePlan,
        definition: ScheduledTask
    ) throws -> ScheduledTaskClaimResult {
        let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
        definition.pendingOccurrenceAt = ScheduledTaskRecurrenceCalculator.latestCoalescedOccurrence(
            existing: definition.pendingOccurrenceAt,
            candidate: duePlan.occurrenceAt
        )
        if duePlan.consumesNextOccurrence {
            definition.nextOccurrenceAt = duePlan.nextOccurrenceAt
        }
        try persistClaimMutation(
            definition: definition,
            restoring: definitionSnapshot
        )
        return .overlapped(pendingOccurrenceAt: duePlan.occurrenceAt)
    }

    func applyConsumedOccurrences(
        _ duePlan: DuePlan,
        to definition: ScheduledTask
    ) {
        if duePlan.consumesNextOccurrence {
            definition.nextOccurrenceAt = duePlan.nextOccurrenceAt
        }
        if duePlan.consumesPendingOccurrence {
            definition.pendingOccurrenceAt = nil
        }
        if definition.recurrence?.isOneShot == true {
            definition.state = .completed
            definition.nextOccurrenceAt = nil
        }
    }

    func persistRunNowClaim(
        _ request: ScheduledTaskRunNowRequest,
        definition: ScheduledTask,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws -> ScheduledTaskClaimResult {
        let occurrenceID = runNowOccurrenceID(request)
        if let existingRun = resolveRun(occurrenceID: occurrenceID) {
            return .alreadyClaimed(runID: existingRun.persistentModelID)
        }

        let definitionSnapshot = ScheduledTaskClaimMutationSnapshot(definition)
        let run = ScheduledTaskRun(
            snapshotting: definition,
            occurrenceID: occurrenceID,
            occurrenceAt: request.occurrenceAt,
            triggeredAt: request.triggeredAt,
            triggerKind: .runNow,
            workspaceIdentitySnapshot: workspaceIdentities
        )
        try applyRunNowConsumption(request, to: definition)
        modelContext.insert(run)
        try persistClaimMutation(
            definition: definition,
            restoring: definitionSnapshot,
            insertedRun: run
        )
        return .claimed(runID: run.persistentModelID)
    }

    func applyRunNowConsumption(
        _ request: ScheduledTaskRunNowRequest,
        to definition: ScheduledTask
    ) throws {
        guard request.consumesScheduledOccurrence else {
            return
        }
        if let pendingOccurrenceAt = definition.pendingOccurrenceAt,
           pendingOccurrenceAt <= request.triggeredAt {
            definition.pendingOccurrenceAt = nil
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
        definition.pauseReason = resolvedReason
        definition.lastError = resolvedReason
        definition.revision += 1
        definition.modifiedAt = actionDate
        try persistInvalidDefinitionPause(
            definition: definition,
            restoring: definitionSnapshot
        )
        return .paused(reason: resolvedReason)
    }

}
