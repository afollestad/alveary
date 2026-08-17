import Foundation
import SwiftData

@MainActor
final class ScheduledTaskMutationService {
    // Internal rather than private: the `+Validation` companion reads them.
    let modelContext: ModelContext
    let recurrenceCalculator: ScheduledTaskRecurrenceCalculator
    private let notificationCenter: NotificationCenter
    private let currentTimeZone: @MainActor () -> TimeZone

    init(
        modelContext: ModelContext,
        recurrenceCalculator: ScheduledTaskRecurrenceCalculator = ScheduledTaskRecurrenceCalculator(),
        notificationCenter: NotificationCenter = .default,
        currentTimeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.modelContext = modelContext
        self.recurrenceCalculator = recurrenceCalculator
        self.notificationCenter = notificationCenter
        self.currentTimeZone = currentTimeZone
    }

    @discardableResult
    func create(
        edit: ScheduledTaskDefinitionEdit,
        at actionDate: Date = .now,
        consumingProposalID: String? = nil
    ) throws -> ScheduledTask {
        try flushPendingChanges()
        let timeZoneIdentifier = currentTimeZone().identifier
        try validate(edit, timeZoneIdentifier: timeZoneIdentifier)
        let proposal = try proposalToConsume(id: consumingProposalID)
        let nextOccurrence = try recurrenceCalculator.nextOccurrence(
            strictlyAfter: actionDate,
            recurrence: edit.recurrence,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let definition = ScheduledTask(
            title: edit.title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: edit.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: edit.destination,
            state: nextOccurrence == nil ? .completed : .active,
            recurrence: edit.recurrence,
            timeZoneIdentifier: timeZoneIdentifier,
            providerID: edit.providerID,
            model: edit.model,
            effort: edit.effort,
            permissionMode: edit.permissionMode,
            workspaceKind: edit.destination == .existingThread ? .privateWorkspace : edit.workspaceKind,
            workspaceStrategy: edit.workspaceStrategy,
            grantedRoots: edit.grantedRoots,
            project: edit.destination != .existingThread && edit.workspaceKind == .project ? edit.project : nil,
            nextOccurrenceAt: nextOccurrence,
            createdAt: actionDate,
            modifiedAt: actionDate,
            targetThread: edit.destination == .existingThread ? edit.targetThread : nil
        )
        // The model initializer normalizes paths. Restore the validated literal snapshot so a
        // post-validation symlink swap cannot rewrite the user's authorization boundary.
        definition.grantedRoots = edit.grantedRoots
        // Only a projectless new-thread schedule places its created threads in a section; a
        // Project-backed thread nests under the Project and an existing target keeps its own row.
        definition.threadSection = edit.destination != .existingThread && edit.workspaceKind == .privateWorkspace
            ? edit.threadSection
            : nil
        let consumesProposal = proposal != nil

        let outcomeTarget = proposal.map(ScheduledTaskProposalOutcomeTarget.init(proposal:))
        do {
            try pinTargetThreadIfNeeded(edit)
            modelContext.insert(definition)
            if let proposal {
                modelContext.delete(proposal)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        recordConfirmedOutcome(outcomeTarget, definitionID: definition.id, at: actionDate)
        publishChange(definitionID: definition.id)
        publishProposalConsumption(if: consumesProposal)
        return definition
    }

    func pause(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now,
        consumingProposalID: String? = nil
    ) throws {
        let didChange = try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            consumingProposalID: consumingProposalID
        ) { definition in
            guard definition.state != .completed else {
                throw ScheduledTaskMutationError.scheduleIsCompleted
            }
            guard definition.state != .paused else {
                return false
            }
            definition.timeZoneIdentifier = self.currentTimeZone().identifier
            let nextOccurrence = self.nextOccurrenceIfValid(
                for: definition,
                strictlyAfter: actionDate
            )
            definition.state = .paused
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.targetWaitStartedAt = nil
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
        at actionDate: Date = .now,
        consumingProposalID: String? = nil
    ) throws {
        let didChange = try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            consumingProposalID: consumingProposalID
        ) { definition in
            guard definition.state == .paused else {
                throw ScheduledTaskMutationError.scheduleIsNotPaused
            }
            guard let destination = definition.decodedDestination else {
                throw ScheduledTaskMutationError.invalidDestination
            }
            if destination != .existingThread,
               definition.workspaceKind == .project,
               definition.project == nil {
                throw ScheduledTaskMutationError.projectWorkspaceRequiresProject
            }
            if destination == .existingThread,
               definition.targetThread == nil {
                throw ScheduledTaskMutationError.existingThreadRequiresAvailableThread
            }
            guard let recurrence = definition.recurrence else {
                throw ScheduledTaskMutationError.invalidRecurrence
            }
            let timeZoneIdentifier = self.currentTimeZone().identifier
            let nextOccurrence = try self.recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: recurrence,
                timeZoneIdentifier: timeZoneIdentifier
            )
            definition.timeZoneIdentifier = timeZoneIdentifier
            definition.state = nextOccurrence == nil ? .completed : .active
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.targetWaitStartedAt = nil
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
        at actionDate: Date = .now,
        consumingProposalID: String? = nil
    ) throws {
        let didChange = try mutateDefinition(
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            consumingProposalID: consumingProposalID
        ) { definition in
            let timeZoneIdentifier = self.currentTimeZone().identifier
            try self.validate(edit, timeZoneIdentifier: timeZoneIdentifier)
            try self.pinTargetThreadIfNeeded(edit)
            let nextOccurrence = try self.recurrenceCalculator.nextOccurrence(
                strictlyAfter: actionDate,
                recurrence: edit.recurrence,
                timeZoneIdentifier: timeZoneIdentifier
            )
            // Computed before any assignment because it compares stored values.
            let preservesReuseLink = self.preservesReuseLink(of: definition, applying: edit)
            let wasPaused = definition.state == .paused
            definition.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            definition.prompt = edit.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            definition.recurrence = edit.recurrence
            definition.timeZoneIdentifier = timeZoneIdentifier
            definition.providerID = edit.providerID
            definition.model = edit.model
            definition.effort = edit.effort
            definition.permissionMode = edit.permissionMode
            definition.workspaceKind = edit.destination == .existingThread ? .privateWorkspace : edit.workspaceKind
            definition.workspaceStrategy = edit.workspaceStrategy
            definition.grantedRoots = edit.grantedRoots
            definition.destination = edit.destination
            definition.project = edit.destination != .existingThread && edit.workspaceKind == .project ? edit.project : nil
            definition.targetThread = edit.destination == .existingThread ? edit.targetThread : nil
            definition.reusedThread = preservesReuseLink ? definition.reusedThread : nil
            definition.threadSection = edit.destination != .existingThread && edit.workspaceKind == .privateWorkspace
                ? edit.threadSection
                : nil
            definition.state = wasPaused ? .paused : (nextOccurrence == nil ? .completed : .active)
            definition.nextOccurrenceAt = nextOccurrence
            definition.pendingOccurrenceAt = nil
            definition.targetWaitStartedAt = nil
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
        expectedRevision: Int? = nil,
        consumingProposalID: String? = nil
    ) throws {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        let proposal = try proposalToConsume(id: consumingProposalID)
        let consumesProposal = proposal != nil
        let outcomeTarget = proposal.map(ScheduledTaskProposalOutcomeTarget.init(proposal:))
        do {
            modelContext.delete(definition)
            if let proposal {
                modelContext.delete(proposal)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        // A deleted definition cannot be opened, so the marker records no target.
        recordConfirmedOutcome(outcomeTarget, definitionID: nil)
        publishChange(definitionID: definitionID)
        publishProposalConsumption(if: consumesProposal)
    }

    func prepareRunNow(
        definitionID: String,
        expectedRevision: Int? = nil,
        at actionDate: Date = .now,
        idempotencyKey: String? = nil
    ) throws -> ScheduledTaskRunNowRequest {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        let didRebaseTimeZone = ScheduledTaskLocalTimeZoneRebaser.rebase(
            definition,
            to: currentTimeZone().identifier,
            at: actionDate,
            recurrenceCalculator: recurrenceCalculator
        )
        if didRebaseTimeZone {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
            publishChange(definitionID: definitionID)
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        guard definition.decodedDestination != nil else {
            throw ScheduledTaskMutationError.invalidDestination
        }
        guard !definition.runs.contains(where: { !$0.hasKnownTerminalStatus }) else {
            throw ScheduledTaskMutationError.runNowBlockedByActiveRun
        }
        guard definition.targetWaitStartedAt == nil else {
            throw ScheduledTaskMutationError.runNowBlockedByTargetWait
        }

        return ScheduledTaskRunNowRequest.prepare(
            definition: definition,
            triggeredAt: actionDate,
            recurrenceCalculator: recurrenceCalculator,
            idempotencyKey: idempotencyKey
        )
    }

    func consumeProposal(id: String) throws {
        try flushPendingChanges()
        guard let proposal = modelContext.resolveScheduledTaskProposal(id: id) else {
            throw ScheduledTaskMutationError.proposalNotFound
        }
        let outcomeTarget = ScheduledTaskProposalOutcomeTarget(proposal: proposal)
        do {
            modelContext.delete(proposal)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        recordConfirmedOutcome(outcomeTarget, definitionID: proposal.targetDefinitionID)
        notificationCenter.postScheduledTaskProposalsChanged(object: self)
    }
}

extension ScheduledTask {
    static let projectDeletedPauseReason = "Source project was deleted."

    func pauseForProjectDeletion(at actionDate: Date) {
        state = .paused
        project = nil
        nextOccurrenceAt = nil
        pendingOccurrenceAt = nil
        targetWaitStartedAt = nil
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
        consumingProposalID: String?,
        mutation: (ScheduledTask) throws -> Bool
    ) throws -> Bool {
        try flushPendingChanges()
        guard let definition = modelContext.resolveScheduledTask(id: definitionID) else {
            throw ScheduledTaskMutationError.definitionNotFound
        }
        try validateRevision(definition, expectedRevision: expectedRevision)
        let proposal = try proposalToConsume(id: consumingProposalID)
        let consumesProposal = proposal != nil
        let outcomeTarget = proposal.map(ScheduledTaskProposalOutcomeTarget.init(proposal:))
        do {
            let didChange = try mutation(definition)
            if let proposal {
                modelContext.delete(proposal)
            }
            guard didChange || proposal != nil else {
                return false
            }
            try modelContext.save()
            recordConfirmedOutcome(outcomeTarget, definitionID: definitionID)
            publishProposalConsumption(if: consumesProposal)
            return didChange
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Stamps the durable transcript outcome right after the proposal is consumed.
    func recordConfirmedOutcome(
        _ target: ScheduledTaskProposalOutcomeTarget?,
        definitionID: String?,
        at timestamp: Date = .now
    ) {
        guard let target else {
            return
        }
        ScheduledTaskProposalOutcomeRecorder.record(
            target,
            outcome: .confirmed,
            definitionID: definitionID,
            in: modelContext,
            at: timestamp
        )
    }

    func publishChange(definitionID: String) {
        notificationCenter.postScheduledTasksChanged(
            object: self,
            definitionID: definitionID
        )
    }

    func proposalToConsume(id: String?) throws -> ScheduledTaskProposal? {
        guard let id else {
            return nil
        }
        guard let proposal = modelContext.resolveScheduledTaskProposal(id: id) else {
            throw ScheduledTaskMutationError.proposalNotFound
        }
        return proposal
    }

    func publishProposalConsumption(if consumedProposal: Bool) {
        guard consumedProposal else {
            return
        }
        notificationCenter.postScheduledTaskProposalsChanged(object: self)
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
