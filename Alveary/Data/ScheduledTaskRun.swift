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

struct ScheduledWorktreeCleanupProvenance: Equatable, Sendable {
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
    var timeZoneIdentifierSnapshot: String
    var providerIDSnapshot: String
    var modelSnapshot: String?
    var effortSnapshot: String
    var permissionModeSnapshot: String
    var workspaceKindRawValueSnapshot: String
    var workspaceStrategyRawValueSnapshot: String
    var projectPathSnapshot: String?
    var projectBaseRefSnapshot: String?
    var projectRemoteNameSnapshot: String?
    var grantedRootsSnapshot: [String]
    var workspaceIdentitySnapshotJSON: String?
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
        projectBaseRefSnapshot: String? = nil,
        projectRemoteNameSnapshot: String? = nil,
        grantedRootsSnapshot: [String] = [],
        workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot? = nil,
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
        self.projectBaseRefSnapshot = projectBaseRefSnapshot
        self.projectRemoteNameSnapshot = projectRemoteNameSnapshot
        self.grantedRootsSnapshot = ScheduledTask.normalizedUniquePaths(grantedRootsSnapshot)
        self.workspaceIdentitySnapshotJSON = Self.encodeWorkspaceIdentitySnapshot(workspaceIdentitySnapshot)
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
            projectBaseRefSnapshot: definition.project?.baseRef,
            projectRemoteNameSnapshot: definition.project?.remoteName,
            grantedRootsSnapshot: definition.grantedRoots,
            workspaceIdentitySnapshot: workspaceIdentitySnapshot,
            scheduledTask: definition,
            thread: thread
        )
        projectPathSnapshot = definition.project?.path
        grantedRootsSnapshot = definition.grantedRoots
    }

    var triggerKind: ScheduledTaskRunTriggerKind? {
        get { ScheduledTaskRunTriggerKind(rawValue: triggerKindRawValue) }
        set {
            if let newValue {
                triggerKindRawValue = newValue.rawValue
            }
        }
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

    var pendingWorktreeCleanup: ScheduledWorktreeCleanupProvenance? {
        ScheduledWorktreeCleanupProvenance(
            sourceProjectPath: pendingWorktreeCleanupSourceProjectPath,
            worktreePath: pendingWorktreeCleanupPath,
            branch: pendingWorktreeCleanupBranch,
            sourceProjectIdentitySystemNumber: pendingCleanupSourceIdentitySystemNumber,
            sourceProjectIdentityFileNumber: pendingCleanupSourceIdentityFileNumber,
            worktreeIdentitySystemNumber: pendingCleanupWorktreeSystemNumber,
            worktreeIdentityFileNumber: pendingCleanupWorktreeFileNumber,
            branchIsOwned: pendingWorktreeCleanupBranchIsOwned,
            branchOID: pendingWorktreeCleanupBranchOID,
            ownershipMarkerID: pendingWorktreeCleanupOwnershipMarkerID,
            ownershipSourceProjectPath: pendingCleanupOwnershipSourceProjectPath
        )
    }

    var workspaceIdentitySnapshot: ScheduledTaskWorkspaceIdentitySnapshot? {
        get {
            guard let workspaceIdentitySnapshotJSON,
                  let data = workspaceIdentitySnapshotJSON.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(ScheduledTaskWorkspaceIdentitySnapshot.self, from: data)
        }
        set {
            workspaceIdentitySnapshotJSON = Self.encodeWorkspaceIdentitySnapshot(newValue)
        }
    }

    var hasValidWorkspaceIdentityProvenance: Bool {
        guard let workspaceKindSnapshot,
              workspaceStrategySnapshot != nil,
              let workspaceIdentitySnapshot else {
            return false
        }
        return workspaceIdentitySnapshot.matchesConfiguration(
            workspaceKind: workspaceKindSnapshot,
            projectPath: projectPathSnapshot,
            grantedRootPaths: grantedRootsSnapshot
        )
    }

    var hasPendingWorktreeCleanupMetadata: Bool {
        pendingWorktreeCleanupSourceProjectPath != nil ||
            pendingWorktreeCleanupPath != nil ||
            pendingWorktreeCleanupBranch != nil ||
            pendingCleanupSourceIdentitySystemNumber != nil ||
            pendingCleanupSourceIdentityFileNumber != nil ||
            pendingCleanupWorktreeSystemNumber != nil ||
            pendingCleanupWorktreeFileNumber != nil ||
            pendingWorktreeCleanupBranchIsOwned != nil ||
            pendingWorktreeCleanupBranchOID != nil ||
            pendingWorktreeCleanupOwnershipMarkerID != nil ||
            pendingCleanupOwnershipSourceProjectPath != nil
    }

    func setPendingWorktreeCleanup(_ provenance: ScheduledWorktreeCleanupProvenance) {
        pendingWorktreeCleanupSourceProjectPath = provenance.sourceProjectPath
        pendingWorktreeCleanupPath = provenance.worktreePath
        pendingWorktreeCleanupBranch = provenance.branch
        pendingCleanupSourceIdentitySystemNumber = String(provenance.sourceProjectIdentity.systemNumber)
        pendingCleanupSourceIdentityFileNumber = String(provenance.sourceProjectIdentity.fileNumber)
        pendingCleanupWorktreeSystemNumber = provenance.worktreeIdentity.map { String($0.systemNumber) }
        pendingCleanupWorktreeFileNumber = provenance.worktreeIdentity.map { String($0.fileNumber) }
        pendingWorktreeCleanupBranchIsOwned = provenance.branchIsOwned
        pendingWorktreeCleanupBranchOID = provenance.branchOID
        pendingWorktreeCleanupOwnershipMarkerID = provenance.ownershipMarkerID
        pendingCleanupOwnershipSourceProjectPath = provenance.ownershipSourceProjectPath
    }

    func clearPendingWorktreeOwnershipCleanup() {
        pendingCleanupWorktreeSystemNumber = nil
        pendingCleanupWorktreeFileNumber = nil
        pendingWorktreeCleanupOwnershipMarkerID = nil
        pendingCleanupOwnershipSourceProjectPath = nil
    }

    func clearPendingWorktreeCleanup() {
        pendingWorktreeCleanupSourceProjectPath = nil
        pendingWorktreeCleanupPath = nil
        pendingWorktreeCleanupBranch = nil
        pendingCleanupSourceIdentitySystemNumber = nil
        pendingCleanupSourceIdentityFileNumber = nil
        pendingWorktreeCleanupBranchIsOwned = nil
        pendingWorktreeCleanupBranchOID = nil
        clearPendingWorktreeOwnershipCleanup()
    }

    private static func encodeWorkspaceIdentitySnapshot(
        _ snapshot: ScheduledTaskWorkspaceIdentitySnapshot?
    ) -> String? {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
