import Foundation
import SwiftData

@MainActor
extension ScheduledTaskSchedulerEngine {
    func resolveRun(occurrenceID: String) -> ScheduledTaskRun? {
        let descriptor = FetchDescriptor<ScheduledTaskRun>(
            predicate: #Predicate { run in
                run.occurrenceID == occurrenceID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func savePendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }

    func persistClaimMutation(
        definition: ScheduledTask,
        restoring snapshot: ScheduledTaskClaimMutationSnapshot,
        insertedRun: ScheduledTaskRun? = nil
    ) throws {
        do {
            try saveState(modelContext)
        } catch {
            // Restore only scheduler-owned claim fields so unrelated shared-context edits survive.
            snapshot.restore(definition)
            if let insertedRun {
                insertedRun.scheduledTask = nil
                modelContext.delete(insertedRun)
            }
            throw error
        }
    }

    func persistInvalidDefinitionPause(
        definition: ScheduledTask,
        restoring snapshot: ScheduledTaskPauseSnapshot
    ) throws {
        do {
            try saveState(modelContext)
        } catch {
            snapshot.restore(definition)
            throw error
        }
    }
}

struct ScheduledTaskClaimMutationSnapshot {
    let stateRawValue: String
    let nextOccurrenceAt: Date?
    let pendingOccurrenceAt: Date?
    let targetWaitStartedAt: Date?

    @MainActor
    init(_ definition: ScheduledTask) {
        stateRawValue = definition.stateRawValue
        nextOccurrenceAt = definition.nextOccurrenceAt
        pendingOccurrenceAt = definition.pendingOccurrenceAt
        targetWaitStartedAt = definition.targetWaitStartedAt
    }

    @MainActor
    func restore(_ definition: ScheduledTask) {
        definition.stateRawValue = stateRawValue
        definition.nextOccurrenceAt = nextOccurrenceAt
        definition.pendingOccurrenceAt = pendingOccurrenceAt
        definition.targetWaitStartedAt = targetWaitStartedAt
    }
}

struct ScheduledTaskPauseSnapshot {
    let stateRawValue: String
    let nextOccurrenceAt: Date?
    let pendingOccurrenceAt: Date?
    let targetWaitStartedAt: Date?
    let pauseReason: String?
    let lastError: String?
    let revision: Int
    let modifiedAt: Date

    @MainActor
    init(_ definition: ScheduledTask) {
        stateRawValue = definition.stateRawValue
        nextOccurrenceAt = definition.nextOccurrenceAt
        pendingOccurrenceAt = definition.pendingOccurrenceAt
        targetWaitStartedAt = definition.targetWaitStartedAt
        pauseReason = definition.pauseReason
        lastError = definition.lastError
        revision = definition.revision
        modifiedAt = definition.modifiedAt
    }

    @MainActor
    func restore(_ definition: ScheduledTask) {
        definition.stateRawValue = stateRawValue
        definition.nextOccurrenceAt = nextOccurrenceAt
        definition.pendingOccurrenceAt = pendingOccurrenceAt
        definition.targetWaitStartedAt = targetWaitStartedAt
        definition.pauseReason = pauseReason
        definition.lastError = lastError
        definition.revision = revision
        definition.modifiedAt = modifiedAt
    }
}
