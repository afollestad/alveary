import Foundation
import SwiftData

extension Notification.Name {
    static let scheduledTasksChanged = Notification.Name("scheduledTasksChanged")
}

enum ScheduledTasksChangeUserInfoKey {
    static let definitionID = "definitionID"
    static let schedulerClaimResolved = "schedulerClaimResolved"
}

extension NotificationCenter {
    func postScheduledTasksChanged(
        object: Any? = nil,
        definitionID: String? = nil,
        schedulerClaimResolved: Bool = false
    ) {
        var userInfo: [AnyHashable: Any] = [:]
        if let definitionID {
            userInfo[ScheduledTasksChangeUserInfoKey.definitionID] = definitionID
        }
        if schedulerClaimResolved {
            userInfo[ScheduledTasksChangeUserInfoKey.schedulerClaimResolved] = true
        }
        post(
            name: .scheduledTasksChanged,
            object: object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}

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

    @MainActor
    static func prepare(
        definition: ScheduledTask,
        triggeredAt: Date,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    ) -> Self {
        let scheduledOccurrence = latestScheduledOccurrence(
            definition: definition,
            through: triggeredAt,
            recurrenceCalculator: recurrenceCalculator
        )
        let pendingOccurrence = definition.pendingOccurrenceAt.flatMap { occurrence in
            occurrence <= triggeredAt ? occurrence : nil
        }

        let occurrenceAt: Date
        let occurrenceSource: ScheduledTaskRunNowOccurrenceSource
        switch (scheduledOccurrence, pendingOccurrence) {
        case let (scheduled?, pending?) where pending > scheduled:
            occurrenceAt = pending
            occurrenceSource = .pending
        case let (scheduled?, _):
            occurrenceAt = scheduled
            occurrenceSource = .scheduled
        case let (nil, pending?):
            occurrenceAt = pending
            occurrenceSource = .pending
        case (nil, nil):
            occurrenceAt = triggeredAt
            occurrenceSource = .manual
        }

        return Self(
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: occurrenceAt,
            triggeredAt: triggeredAt,
            occurrenceSource: occurrenceSource
        )
    }

    @MainActor
    private static func latestScheduledOccurrence(
        definition: ScheduledTask,
        through actionDate: Date,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    ) -> Date? {
        guard let firstOccurrence = definition.nextOccurrenceAt,
              firstOccurrence <= actionDate else {
            return nil
        }
        guard let recurrence = definition.recurrence,
              let window = try? recurrenceCalculator.coalescedOccurrences(
                  startingAt: firstOccurrence,
                  through: actionDate,
                  recurrence: recurrence,
                  timeZoneIdentifier: definition.timeZoneIdentifier
              ) else {
            // Let the scheduler preflight pause malformed definitions instead of
            // turning Run now preparation into a separate validation path.
            return firstOccurrence
        }
        return window.latestDueOccurrence ?? firstOccurrence
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
    private let notificationCenter: NotificationCenter

    init(
        modelContext: ModelContext,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.modelContext = modelContext
        self.recurrenceCalculator = recurrenceCalculator
        self.notificationCenter = notificationCenter
    }

    @discardableResult
    func create(
        edit: ScheduledTaskDefinitionEdit,
        at actionDate: Date = .now
    ) throws -> ScheduledTask {
        try flushPendingChanges()
        try validate(edit)
        let nextOccurrence = try recurrenceCalculator.nextOccurrence(
            strictlyAfter: actionDate,
            recurrence: edit.recurrence,
            timeZoneIdentifier: edit.timeZoneIdentifier
        )
        let definition = ScheduledTask(
            title: edit.title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: edit.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            state: nextOccurrence == nil ? .completed : .active,
            recurrence: edit.recurrence,
            timeZoneIdentifier: edit.timeZoneIdentifier,
            providerID: edit.providerID,
            model: edit.model,
            effort: edit.effort,
            permissionMode: edit.permissionMode,
            workspaceKind: edit.workspaceKind,
            workspaceStrategy: edit.workspaceStrategy,
            grantedRoots: edit.grantedRoots,
            project: edit.workspaceKind == .project ? edit.project : nil,
            nextOccurrenceAt: nextOccurrence,
            createdAt: actionDate,
            modifiedAt: actionDate
        )

        do {
            modelContext.insert(definition)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        publishChange(definitionID: definition.id)
        return definition
    }

    func pause(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now
    ) throws {
        let didChange = try mutateDefinition(
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
        if didChange {
            publishChange(definitionID: definitionID)
        }
    }

    func resume(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now
    ) throws {
        let didChange = try mutateDefinition(
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
        if didChange {
            publishChange(definitionID: definitionID)
        }
    }

    func edit(
        definitionID: String,
        expectedRevision: Int? = nil,
        edit: ScheduledTaskDefinitionEdit,
        at actionDate: Date = .now
    ) throws {
        let didChange = try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision
        ) { definition in
            try self.validate(edit)
            let nextOccurrence = try self.recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: edit.recurrence,
                timeZoneIdentifier: edit.timeZoneIdentifier
            )
            let wasPaused = definition.state == .paused
            definition.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            definition.prompt = edit.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if didChange {
            publishChange(definitionID: definitionID)
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
        publishChange(definitionID: definitionID)
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
        guard !definition.runs.contains(where: { !$0.hasKnownTerminalStatus }) else {
            throw ScheduledTaskMutationError.runNowBlockedByActiveRun
        }

        return ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: actionDate,
            recurrenceCalculator: recurrenceCalculator
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
    ) throws -> Bool {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        do {
            guard try mutation(definition) else {
                return false
            }
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func validate(_ edit: ScheduledTaskDefinitionEdit) throws {
        if edit.workspaceKind == .project, edit.project == nil {
            throw ScheduledTaskMutationError.projectWorkspaceRequiresProject
        }
        try recurrenceCalculator.validate(
            edit.recurrence,
            timeZoneIdentifier: edit.timeZoneIdentifier
        )
    }

    func publishChange(definitionID: String) {
        notificationCenter.postScheduledTasksChanged(
            object: self,
            definitionID: definitionID
        )
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
