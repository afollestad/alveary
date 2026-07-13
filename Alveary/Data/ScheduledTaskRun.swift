import Foundation
import SwiftData

enum ScheduledTaskRunTriggerKind: String, Codable, CaseIterable, Sendable {
    case scheduled
    case runNow
}

enum ScheduledTaskRunStatus: String, Codable, CaseIterable, Sendable {
    case claimed
    case preparing
    case running
    case waiting
    case success
    case failure
    case interrupted
    case skipped

    var isTerminal: Bool {
        switch self {
        case .claimed, .preparing, .running, .waiting:
            false
        case .success, .failure, .interrupted, .skipped:
            true
        }
    }
}

@Model
final class ScheduledTaskRun {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var occurrenceID: String
    @Attribute(.unique) var triggerID: String
    var definitionID: String
    var definitionRevision: Int
    var occurrenceAt: Date
    var triggeredAt: Date
    var triggerKindRawValue: String
    var statusRawValue: String
    var titleSnapshot: String
    var promptSnapshot: String
    var timeZoneIdentifierSnapshot: String
    var providerIDSnapshot: String
    var modelSnapshot: String?
    var effortSnapshot: String
    var permissionModeSnapshot: String
    var workspaceKindRawValueSnapshot: String
    var workspaceStrategyRawValueSnapshot: String
    var projectPathSnapshot: String?
    var grantedRootsSnapshot: [String]
    var preparedWorkspaceRoot: String?
    var preparedOwnershipStrategyRawValue: String?
    var preparedWorkspaceMarkerID: String?
    var claimedAt: Date
    var preparationStartedAt: Date?
    var startedAt: Date?
    var waitingAt: Date?
    var finishedAt: Date?
    var lastError: String?
    var scheduledTask: ScheduledTask?
    @Relationship(deleteRule: .nullify, inverse: \AgentThread.scheduledTaskRun) var thread: AgentThread?

    init(
        id: String = UUID().uuidString,
        occurrenceID: String,
        triggerID: String = UUID().uuidString,
        definitionID: String,
        definitionRevision: Int,
        occurrenceAt: Date,
        triggeredAt: Date = .now,
        triggerKind: ScheduledTaskRunTriggerKind,
        status: ScheduledTaskRunStatus = .claimed,
        titleSnapshot: String,
        promptSnapshot: String,
        timeZoneIdentifierSnapshot: String,
        providerIDSnapshot: String,
        modelSnapshot: String? = nil,
        effortSnapshot: String,
        permissionModeSnapshot: String,
        workspaceKindSnapshot: ScheduledTaskWorkspaceKind,
        workspaceStrategySnapshot: ScheduledTaskWorkspaceStrategy,
        projectPathSnapshot: String? = nil,
        grantedRootsSnapshot: [String] = [],
        preparedWorkspaceRoot: String? = nil,
        preparedWorkspaceOwnershipStrategy: TaskWorkspaceOwnershipStrategy? = nil,
        preparedWorkspaceMarkerID: String? = nil,
        claimedAt: Date = .now,
        preparationStartedAt: Date? = nil,
        startedAt: Date? = nil,
        waitingAt: Date? = nil,
        finishedAt: Date? = nil,
        lastError: String? = nil,
        scheduledTask: ScheduledTask? = nil,
        thread: AgentThread? = nil
    ) {
        self.id = id
        self.occurrenceID = occurrenceID
        self.triggerID = triggerID
        self.definitionID = definitionID
        self.definitionRevision = definitionRevision
        self.occurrenceAt = occurrenceAt
        self.triggeredAt = triggeredAt
        self.triggerKindRawValue = triggerKind.rawValue
        self.statusRawValue = status.rawValue
        self.titleSnapshot = titleSnapshot
        self.promptSnapshot = promptSnapshot
        self.timeZoneIdentifierSnapshot = timeZoneIdentifierSnapshot
        self.providerIDSnapshot = providerIDSnapshot
        self.modelSnapshot = modelSnapshot
        self.effortSnapshot = effortSnapshot
        self.permissionModeSnapshot = permissionModeSnapshot
        self.workspaceKindRawValueSnapshot = workspaceKindSnapshot.rawValue
        self.workspaceStrategyRawValueSnapshot = workspaceStrategySnapshot.rawValue
        self.projectPathSnapshot = projectPathSnapshot.map(CanonicalPath.normalize)
        self.grantedRootsSnapshot = ScheduledTask.normalizedUniquePaths(grantedRootsSnapshot)
        self.preparedWorkspaceRoot = preparedWorkspaceRoot.map(CanonicalPath.normalize)
        self.preparedOwnershipStrategyRawValue = preparedWorkspaceOwnershipStrategy?.rawValue
        self.preparedWorkspaceMarkerID = preparedWorkspaceMarkerID
        self.claimedAt = claimedAt
        self.preparationStartedAt = preparationStartedAt
        self.startedAt = startedAt
        self.waitingAt = waitingAt
        self.finishedAt = finishedAt
        self.lastError = lastError
        self.scheduledTask = scheduledTask
        self.thread = thread
    }
}

extension ScheduledTaskRun {
    convenience init(
        snapshotting definition: ScheduledTask,
        occurrenceID: String,
        triggerID: String = UUID().uuidString,
        occurrenceAt: Date,
        triggeredAt: Date = .now,
        triggerKind: ScheduledTaskRunTriggerKind,
        status: ScheduledTaskRunStatus = .claimed,
        thread: AgentThread? = nil
    ) {
        self.init(
            occurrenceID: occurrenceID,
            triggerID: triggerID,
            definitionID: definition.id,
            definitionRevision: definition.revision,
            occurrenceAt: occurrenceAt,
            triggeredAt: triggeredAt,
            triggerKind: triggerKind,
            status: status,
            titleSnapshot: definition.title,
            promptSnapshot: definition.prompt,
            timeZoneIdentifierSnapshot: definition.timeZoneIdentifier,
            providerIDSnapshot: definition.providerID,
            modelSnapshot: definition.model,
            effortSnapshot: definition.effort,
            permissionModeSnapshot: definition.permissionMode,
            workspaceKindSnapshot: definition.workspaceKind,
            workspaceStrategySnapshot: definition.workspaceStrategy,
            projectPathSnapshot: definition.project?.path,
            grantedRootsSnapshot: definition.grantedRoots,
            scheduledTask: definition,
            thread: thread
        )
    }

    var triggerKind: ScheduledTaskRunTriggerKind {
        get { ScheduledTaskRunTriggerKind(rawValue: triggerKindRawValue) ?? .scheduled }
        set { triggerKindRawValue = newValue.rawValue }
    }

    var status: ScheduledTaskRunStatus {
        get { ScheduledTaskRunStatus(rawValue: statusRawValue) ?? .failure }
        set { statusRawValue = newValue.rawValue }
    }

    var workspaceKindSnapshot: ScheduledTaskWorkspaceKind {
        ScheduledTaskWorkspaceKind(rawValue: workspaceKindRawValueSnapshot) ?? .privateWorkspace
    }

    var workspaceStrategySnapshot: ScheduledTaskWorkspaceStrategy {
        ScheduledTaskWorkspaceStrategy(rawValue: workspaceStrategyRawValueSnapshot) ?? .worktree
    }

    var preparedWorkspaceOwnershipStrategy: TaskWorkspaceOwnershipStrategy? {
        get {
            preparedOwnershipStrategyRawValue.flatMap(TaskWorkspaceOwnershipStrategy.init(rawValue:))
        }
        set {
            preparedOwnershipStrategyRawValue = newValue?.rawValue
        }
    }
}
