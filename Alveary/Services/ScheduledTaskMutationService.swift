import Foundation
import SwiftData

struct ScheduledTaskDefinitionEdit {
    let title: String
    let prompt: String
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String
    let workspaceKind: ScheduledTaskWorkspaceKind
    let workspaceStrategy: ScheduledTaskWorkspaceStrategy
    let grantedRoots: [String]
    let project: Project?
}

enum ScheduledTaskRunNowOccurrenceSource: Equatable, Sendable {
    case scheduled
    case pending
    case manual
}

struct ScheduledTaskRunNowRequest: Equatable, Sendable {
    let definitionID: String
    let definitionRevision: Int
    let occurrenceAt: Date
    let triggeredAt: Date
    let occurrenceSource: ScheduledTaskRunNowOccurrenceSource

    var consumesScheduledOccurrence: Bool {
        occurrenceSource != .manual
    }
}

enum ScheduledTaskMutationError: Error, Equatable, LocalizedError {
    case definitionNotFound
    case invalidRecurrence
    case projectWorkspaceRequiresProject
    case revisionConflict(expected: Int, actual: Int)
    case runNowBlockedByActiveRun
    case scheduleIsCompleted
    case scheduleIsNotPaused

    var errorDescription: String? {
        switch self {
        case .definitionNotFound:
            "Scheduled task no longer exists."
        case .invalidRecurrence:
            "Scheduled task recurrence is invalid."
        case .projectWorkspaceRequiresProject:
            "Project schedules require a project."
        case let .revisionConflict(expected, actual):
            "Scheduled task changed from revision \(expected) to \(actual)."
        case .runNowBlockedByActiveRun:
            "Scheduled task is already running or waiting for input."
        case .scheduleIsCompleted:
            "Completed one-time scheduled tasks cannot be paused."
        case .scheduleIsNotPaused:
            "Only a paused scheduled task can be resumed."
        }
    }
}

@MainActor
final class ScheduledTaskMutationService {
    private let modelContext: ModelContext
    private let recurrenceCalculator: ScheduledTaskRecurrenceCalculator

    init(
        modelContext: ModelContext,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator()
    ) {
        self.modelContext = modelContext
        self.recurrenceCalculator = recurrenceCalculator
    }

    func pause(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now
    ) throws {
        try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision
        ) { definition in
            guard definition.state != .completed else {
                throw ScheduledTaskMutationError.scheduleIsCompleted
            }
            guard definition.state != .paused else {
                return false
            }
            let nextOccurrence = self.nextOccurrenceIfValid(
                for: definition,
                strictlyAfter: actionDate
            )
            definition.state = .paused
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.pauseReason = nil
            definition.lastError = nil
            definition.revision += 1
            definition.modifiedAt = actionDate
            return true
        }
    }

    func resume(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now
    ) throws {
        try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision
        ) { definition in
            guard definition.state == .paused else {
                throw ScheduledTaskMutationError.scheduleIsNotPaused
            }
            if definition.workspaceKind == .project, definition.project == nil {
                throw ScheduledTaskMutationError.projectWorkspaceRequiresProject
            }
            guard let recurrence = definition.recurrence else {
                throw ScheduledTaskMutationError.invalidRecurrence
            }
            let nextOccurrence = try self.recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: recurrence,
                timeZoneIdentifier: definition.timeZoneIdentifier
            )
            definition.state = nextOccurrence == nil ? .completed : .active
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.pauseReason = nil
            definition.lastError = nil
            definition.revision += 1
            definition.modifiedAt = actionDate
            return true
        }
    }

    func edit(
        definitionID: String,
        expectedRevision: Int? = nil,
        edit: ScheduledTaskDefinitionEdit,
        at actionDate: Date = .now
    ) throws {
        try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision
        ) { definition in
            if edit.workspaceKind == .project, edit.project == nil {
                throw ScheduledTaskMutationError.projectWorkspaceRequiresProject
            }
            try self.recurrenceCalculator.validate(
                edit.recurrence,
                timeZoneIdentifier: edit.timeZoneIdentifier
            )
            let nextOccurrence = try self.recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: edit.recurrence,
                timeZoneIdentifier: edit.timeZoneIdentifier
            )
            let wasPaused = definition.state == .paused
            definition.title = edit.title
            definition.prompt = edit.prompt
            definition.recurrence = edit.recurrence
            definition.timeZoneIdentifier = edit.timeZoneIdentifier
            definition.providerID = edit.providerID
            definition.model = edit.model
            definition.effort = edit.effort
            definition.permissionMode = edit.permissionMode
            definition.workspaceKind = edit.workspaceKind
            definition.workspaceStrategy = edit.workspaceStrategy
            definition.grantedRoots = ScheduledTask.normalizedUniquePaths(edit.grantedRoots)
            definition.project = edit.workspaceKind == .project ? edit.project : nil
            definition.state = wasPaused ? .paused : (nextOccurrence == nil ? .completed : .active)
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.pauseReason = nil
            definition.lastError = nil
            definition.revision += 1
            definition.modifiedAt = actionDate
            return true
        }
    }

    func delete(
        definitionID: String,
        expectedRevision: Int? = nil
    ) throws {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        do {
            modelContext.delete(definition)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func prepareRunNow(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now
    ) throws -> ScheduledTaskRunNowRequest {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        guard !definition.runs.contains(where: { !$0.status.isTerminal }) else {
            throw ScheduledTaskMutationError.runNowBlockedByActiveRun
        }

        let dueOccurrences: [(source: ScheduledTaskRunNowOccurrenceSource, date: Date)] = [
            definition.nextOccurrenceAt.map { (.scheduled, $0) },
            definition.pendingOccurrenceAt.map { (.pending, $0) }
        ]
        .compactMap { $0 }
        .filter { $0.date <= actionDate }
        let selectedOccurrence = dueOccurrences.max { lhs, rhs in
            lhs.date < rhs.date
        }

        return ScheduledTaskRunNowRequest(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: selectedOccurrence?.date ?? actionDate,
            triggeredAt: actionDate,
            occurrenceSource: selectedOccurrence?.source ?? .manual
        )
    }
}

extension ScheduledTask {
    static let projectDeletedPauseReason = "Source project was deleted."

    func pauseForProjectDeletion(at actionDate: Date) {
        state = .paused
        project = nil
        nextOccurrenceAt = nil
        pendingOccurrenceAt = nil
        pauseReason = Self.projectDeletedPauseReason
        lastError = nil
        revision += 1
        modifiedAt = actionDate
    }
}

private extension ScheduledTaskMutationService {
    func mutateDefinition(
        definitionID: String,
        expectedRevision: Int?,
        mutation: (ScheduledTask) throws -> Bool
    ) throws {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        do {
            guard try mutation(definition) else {
                return
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func validateRevision(
        _ definition: ScheduledTask,
        expectedRevision: Int?
    ) throws {
        guard let expectedRevision, definition.revision != expectedRevision else {
            return
        }
        throw ScheduledTaskMutationError.revisionConflict(
            expected: expectedRevision,
            actual: definition.revision
        )
    }

    func nextOccurrenceIfValid(
        for definition: ScheduledTask,
        strictlyAfter actionDate: Date
    ) -> Date? {
        guard let recurrence = definition.recurrence else {
            return nil
        }
        return try? recurrenceCalculator.nextOccurrence(
            strictlyAfter: actionDate,
            recurrence: recurrence,
            timeZoneIdentifier: definition.timeZoneIdentifier
        )
    }

    func flushPendingChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try modelContext.save()
    }
}
