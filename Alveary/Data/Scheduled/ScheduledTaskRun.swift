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

struct ScheduledWorktreeCleanupProvenance: Codable, Equatable, Sendable {
    let sourceProjectPath: String
    let worktreePath: String
    let branch: String
    let sourceProjectIdentity: TaskWorkspaceFileSystemIdentity
    let worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    let branchIsOwned: Bool
    let branchOID: String?
    let ownershipMarkerID: String?
    let ownershipSourceProjectPath: String?

    init?(
        sourceProjectPath: String?,
        worktreePath: String?,
        branch: String?,
        sourceProjectIdentitySystemNumber: String?,
        sourceProjectIdentityFileNumber: String?,
        worktreeIdentitySystemNumber: String?,
        worktreeIdentityFileNumber: String?,
        branchIsOwned: Bool?,
        branchOID: String? = nil,
        ownershipMarkerID: String?,
        ownershipSourceProjectPath: String?
    ) {
        guard let sourceProjectPath,
              NSString(string: sourceProjectPath).isAbsolutePath,
              let worktreePath,
              NSString(string: worktreePath).isAbsolutePath,
              let branch,
              !branch.isEmpty,
              let sourceProjectIdentitySystemNumber,
              let systemNumber = UInt64(sourceProjectIdentitySystemNumber),
              let sourceProjectIdentityFileNumber,
              let fileNumber = UInt64(sourceProjectIdentityFileNumber),
              (worktreeIdentitySystemNumber == nil) == (worktreeIdentityFileNumber == nil),
              (ownershipMarkerID == nil) == (ownershipSourceProjectPath == nil) else {
            return nil
        }
        let worktreeIdentity: TaskWorkspaceFileSystemIdentity?
        if let worktreeIdentitySystemNumber,
           let worktreeSystemNumber = UInt64(worktreeIdentitySystemNumber),
           let worktreeIdentityFileNumber,
           let worktreeFileNumber = UInt64(worktreeIdentityFileNumber) {
            worktreeIdentity = TaskWorkspaceFileSystemIdentity(
                systemNumber: worktreeSystemNumber,
                fileNumber: worktreeFileNumber
            )
        } else if worktreeIdentitySystemNumber == nil,
                  worktreeIdentityFileNumber == nil {
            worktreeIdentity = nil
        } else {
            return nil
        }
        self.init(
            sourceProjectPath: sourceProjectPath,
            worktreePath: worktreePath,
            branch: branch,
            sourceProjectIdentity: TaskWorkspaceFileSystemIdentity(
                systemNumber: systemNumber,
                fileNumber: fileNumber
            ),
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: branchIsOwned ?? false,
            branchOID: branchOID,
            ownershipMarkerID: ownershipMarkerID,
            ownershipSourceProjectPath: ownershipSourceProjectPath
        )
    }

    init?(
        sourceProjectPath: String,
        worktreePath: String,
        branch: String,
        sourceProjectIdentity: TaskWorkspaceFileSystemIdentity,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity? = nil,
        branchIsOwned: Bool = true,
        branchOID: String? = nil,
        ownershipMarkerID: String?,
        ownershipSourceProjectPath: String?
    ) {
        guard NSString(string: sourceProjectPath).isAbsolutePath,
              NSString(string: worktreePath).isAbsolutePath,
              !branch.isEmpty,
              branchOID?.isEmpty != true,
              (ownershipMarkerID == nil) == (ownershipSourceProjectPath == nil) else {
            return nil
        }
        self.sourceProjectPath = sourceProjectPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.sourceProjectIdentity = sourceProjectIdentity
        self.worktreeIdentity = worktreeIdentity
        self.branchIsOwned = branchIsOwned
        self.branchOID = branchOID
        self.ownershipMarkerID = ownershipMarkerID
        self.ownershipSourceProjectPath = ownershipSourceProjectPath
    }

    var ownedWorkspaceDescriptor: TaskWorkspaceDescriptor? {
        guard let ownershipMarkerID, let ownershipSourceProjectPath else {
            return nil
        }
        return TaskWorkspaceDescriptor(
            persistedPrimaryRoot: worktreePath,
            persistedGrantedRoots: [],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: ownershipMarkerID,
            persistedSourceProjectPath: ownershipSourceProjectPath
        )
    }

    func recordingBranchOID(_ branchOID: String) -> ScheduledWorktreeCleanupProvenance {
        ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: sourceProjectPath,
            worktreePath: worktreePath,
            branch: branch,
            sourceProjectIdentity: sourceProjectIdentity,
            worktreeIdentity: worktreeIdentity,
            branchIsOwned: branchIsOwned,
            branchOID: branchOID,
            ownershipMarkerID: ownershipMarkerID,
            ownershipSourceProjectPath: ownershipSourceProjectPath
        ) ?? self
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
    var destinationRawValueSnapshot: String = ScheduledTaskDestination.newThread.rawValue
    var targetConversationIDSnapshot: String?
    var targetThreadNameSnapshot: String?
    var timeZoneIdentifierSnapshot: String
    var providerIDSnapshot: String
    var modelSnapshot: String?
    var effortSnapshot: String
    var permissionModeSnapshot: String
    var planModeEnabledSnapshot: Bool?
    var speedModeSnapshot: String?
    var workspaceKindRawValueSnapshot: String
    var workspaceStrategyRawValueSnapshot: String
    var projectPathSnapshot: String?
    var projectBaseRefSnapshot: String?
    var projectRemoteNameSnapshot: String?
    var grantedRootsSnapshot: [String]
    var workspaceIdentitySnapshotJSON: String?
    var workspaceCleanupProvenanceJSON: String?
    var preparedWorkspaceRoot: String?
    var preparedOwnershipStrategyRawValue: String?
    var preparedWorkspaceMarkerID: String?
    var pendingWorktreeCleanupSourceProjectPath: String?
    var pendingWorktreeCleanupPath: String?
    var pendingWorktreeCleanupBranch: String?
    var pendingCleanupSourceIdentitySystemNumber: String?
    var pendingCleanupSourceIdentityFileNumber: String?
    var pendingCleanupWorktreeSystemNumber: String?
    var pendingCleanupWorktreeFileNumber: String?
    var pendingWorktreeCleanupBranchIsOwned: Bool?
    var pendingWorktreeCleanupBranchOID: String?
    var pendingWorktreeCleanupOwnershipMarkerID: String?
    var pendingCleanupOwnershipSourceProjectPath: String?
    var claimedAt: Date
    var preparationStartedAt: Date?
    var startedAt: Date?
    var waitingAt: Date?
    var finishedAt: Date?
    var lastError: String?
    var requiresFinalizationRecovery: Bool = false
    var scheduledTask: ScheduledTask?
    @Relationship(deleteRule: .nullify, inverse: \AgentThread.scheduledTaskRun) var thread: AgentThread?
    var targetThread: AgentThread?

    // swiftlint:disable:next function_body_length
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
        destinationSnapshot: ScheduledTaskDestination = .newThread,
        targetConversationIDSnapshot: String? = nil,
        targetThreadNameSnapshot: String? = nil,
        timeZoneIdentifierSnapshot: String,
        providerIDSnapshot: String,
        modelSnapshot: String? = nil,
        effortSnapshot: String,
        permissionModeSnapshot: String,
        planModeEnabledSnapshot: Bool? = nil,
        speedModeSnapshot: String? = nil,
        workspaceKindSnapshot: ScheduledTaskWorkspaceKind,
        workspaceStrategySnapshot: ScheduledTaskWorkspaceStrategy,
        projectPathSnapshot: String? = nil,
        projectBaseRefSnapshot: String? = nil,
        projectRemoteNameSnapshot: String? = nil,
        grantedRootsSnapshot: [String] = [],
        workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot? = nil,
        workspaceCleanupProvenance: ScheduledWorktreeCleanupProvenance? = nil,
        preparedWorkspaceRoot: String? = nil,
        preparedWorkspaceOwnershipStrategy: TaskWorkspaceOwnershipStrategy? = nil,
        preparedWorkspaceMarkerID: String? = nil,
        pendingWorktreeCleanupSourceProjectPath: String? = nil,
        pendingWorktreeCleanupPath: String? = nil,
        pendingWorktreeCleanupBranch: String? = nil,
        pendingCleanupSourceIdentitySystemNumber: String? = nil,
        pendingCleanupSourceIdentityFileNumber: String? = nil,
        pendingCleanupWorktreeSystemNumber: String? = nil,
        pendingCleanupWorktreeFileNumber: String? = nil,
        pendingWorktreeCleanupBranchIsOwned: Bool? = nil,
        pendingWorktreeCleanupBranchOID: String? = nil,
        pendingWorktreeCleanupOwnershipMarkerID: String? = nil,
        pendingCleanupOwnershipSourceProjectPath: String? = nil,
        claimedAt: Date = .now,
        preparationStartedAt: Date? = nil,
        startedAt: Date? = nil,
        waitingAt: Date? = nil,
        finishedAt: Date? = nil,
        lastError: String? = nil,
        requiresFinalizationRecovery: Bool = false,
        scheduledTask: ScheduledTask? = nil,
        thread: AgentThread? = nil,
        targetThread: AgentThread? = nil
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
        self.destinationRawValueSnapshot = destinationSnapshot.rawValue
        self.targetConversationIDSnapshot = targetConversationIDSnapshot
        self.targetThreadNameSnapshot = targetThreadNameSnapshot
        self.timeZoneIdentifierSnapshot = timeZoneIdentifierSnapshot
        self.providerIDSnapshot = providerIDSnapshot
        self.modelSnapshot = modelSnapshot
        self.effortSnapshot = effortSnapshot
        self.permissionModeSnapshot = permissionModeSnapshot
        self.planModeEnabledSnapshot = planModeEnabledSnapshot
        self.speedModeSnapshot = speedModeSnapshot
        self.workspaceKindRawValueSnapshot = workspaceKindSnapshot.rawValue
        self.workspaceStrategyRawValueSnapshot = workspaceStrategySnapshot.rawValue
        self.projectPathSnapshot = projectPathSnapshot.map(CanonicalPath.normalize)
        self.projectBaseRefSnapshot = projectBaseRefSnapshot
        self.projectRemoteNameSnapshot = projectRemoteNameSnapshot
        self.grantedRootsSnapshot = ScheduledTask.normalizedUniquePaths(grantedRootsSnapshot)
        self.workspaceIdentitySnapshotJSON = Self.encodeWorkspaceIdentitySnapshot(workspaceIdentitySnapshot)
        self.workspaceCleanupProvenanceJSON = Self.encodeWorkspaceCleanupProvenance(workspaceCleanupProvenance)
        self.preparedWorkspaceRoot = preparedWorkspaceRoot.map(CanonicalPath.normalize)
        self.preparedOwnershipStrategyRawValue = preparedWorkspaceOwnershipStrategy?.rawValue
        self.preparedWorkspaceMarkerID = preparedWorkspaceMarkerID
        self.pendingWorktreeCleanupSourceProjectPath = pendingWorktreeCleanupSourceProjectPath
        self.pendingWorktreeCleanupPath = pendingWorktreeCleanupPath
        self.pendingWorktreeCleanupBranch = pendingWorktreeCleanupBranch
        self.pendingCleanupSourceIdentitySystemNumber = pendingCleanupSourceIdentitySystemNumber
        self.pendingCleanupSourceIdentityFileNumber = pendingCleanupSourceIdentityFileNumber
        self.pendingCleanupWorktreeSystemNumber = pendingCleanupWorktreeSystemNumber
        self.pendingCleanupWorktreeFileNumber = pendingCleanupWorktreeFileNumber
        self.pendingWorktreeCleanupBranchIsOwned = pendingWorktreeCleanupBranchIsOwned
        self.pendingWorktreeCleanupBranchOID = pendingWorktreeCleanupBranchOID
        self.pendingWorktreeCleanupOwnershipMarkerID = pendingWorktreeCleanupOwnershipMarkerID
        self.pendingCleanupOwnershipSourceProjectPath = pendingCleanupOwnershipSourceProjectPath
        self.claimedAt = claimedAt
        self.preparationStartedAt = preparationStartedAt
        self.startedAt = startedAt
        self.waitingAt = waitingAt
        self.finishedAt = finishedAt
        self.lastError = lastError
        self.requiresFinalizationRecovery = requiresFinalizationRecovery
        self.scheduledTask = scheduledTask
        self.thread = thread
        self.targetThread = targetThread
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
        workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot? = nil,
        targetSnapshot: ScheduledTaskTargetSnapshot? = nil,
        thread: AgentThread? = nil
    ) {
        guard let destination = definition.decodedDestination else {
            preconditionFailure("Cannot snapshot a scheduled task with an unknown destination")
        }
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
            destinationSnapshot: destination,
            targetConversationIDSnapshot: targetSnapshot?.conversationID,
            targetThreadNameSnapshot: targetSnapshot?.threadName,
            timeZoneIdentifierSnapshot: definition.timeZoneIdentifier,
            providerIDSnapshot: targetSnapshot?.providerID ?? definition.providerID,
            modelSnapshot: targetSnapshot == nil ? definition.model : targetSnapshot?.model,
            effortSnapshot: targetSnapshot?.effort ?? definition.effort,
            permissionModeSnapshot: targetSnapshot?.permissionMode ?? definition.permissionMode,
            planModeEnabledSnapshot: targetSnapshot?.planModeEnabled,
            speedModeSnapshot: targetSnapshot?.speedMode,
            workspaceKindSnapshot: targetSnapshot?.workspaceKind ?? definition.workspaceKind,
            workspaceStrategySnapshot: targetSnapshot?.workspaceStrategy ?? definition.workspaceStrategy,
            projectPathSnapshot: targetSnapshot?.projectPath ?? definition.project?.path,
            projectBaseRefSnapshot: definition.project?.baseRef,
            projectRemoteNameSnapshot: definition.project?.remoteName,
            grantedRootsSnapshot: targetSnapshot?.grantedRoots ?? definition.grantedRoots,
            workspaceIdentitySnapshot: workspaceIdentitySnapshot,
            scheduledTask: definition,
            thread: thread,
            targetThread: definition.targetThread
        )
        projectPathSnapshot = targetSnapshot?.projectPath ?? definition.project?.path
        grantedRootsSnapshot = targetSnapshot?.grantedRoots ?? definition.grantedRoots
    }

    var triggerKind: ScheduledTaskRunTriggerKind? {
        get { ScheduledTaskRunTriggerKind(rawValue: triggerKindRawValue) }
        set {
            if let newValue {
                triggerKindRawValue = newValue.rawValue
            }
        }
    }

    var destinationSnapshot: ScheduledTaskDestination? {
        get { decodedDestinationSnapshot }
        set {
            if let newValue {
                destinationRawValueSnapshot = newValue.rawValue
            }
        }
    }

    var decodedDestinationSnapshot: ScheduledTaskDestination? {
        ScheduledTaskDestination(rawValue: destinationRawValueSnapshot)
    }

    var status: ScheduledTaskRunStatus {
        get { decodedStatus ?? .failure }
        set { statusRawValue = newValue.rawValue }
    }

    var decodedStatus: ScheduledTaskRunStatus? {
        ScheduledTaskRunStatus(rawValue: statusRawValue)
    }

    var hasKnownTerminalStatus: Bool {
        decodedStatus?.isTerminal == true
    }

    var workspaceKindSnapshot: ScheduledTaskWorkspaceKind? {
        ScheduledTaskWorkspaceKind(rawValue: workspaceKindRawValueSnapshot)
    }

    var workspaceStrategySnapshot: ScheduledTaskWorkspaceStrategy? {
        ScheduledTaskWorkspaceStrategy(rawValue: workspaceStrategyRawValueSnapshot)
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
