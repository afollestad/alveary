import Foundation
import SwiftData

struct ScheduledTaskPreflightSnapshot: Equatable, Sendable {
    let definitionID: String
    let definitionRevision: Int
    let scheduledOccurrenceAt: Date
    let recurrence: ScheduledTaskRecurrence
    let timeZoneIdentifier: String
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String
    let workspaceKind: ScheduledTaskWorkspaceKind
    let workspaceStrategy: ScheduledTaskWorkspaceStrategy
    let projectPath: String?
    let projectBaseRef: String?
    let projectRemoteName: String?
    let grantedRoots: [String]
}

struct ScheduledTaskRootIdentitySnapshot: Codable, Equatable, Sendable {
    let path: String
    let identity: TaskWorkspaceFileSystemIdentity
}

struct ScheduledTaskWorkspaceIdentitySnapshot: Codable, Equatable, Sendable {
    let projectRoot: ScheduledTaskRootIdentitySnapshot?
    let grantedRoots: [ScheduledTaskRootIdentitySnapshot]

    init(
        projectRoot: ScheduledTaskRootIdentitySnapshot?,
        grantedRoots: [ScheduledTaskRootIdentitySnapshot]
    ) {
        self.projectRoot = projectRoot
        self.grantedRoots = grantedRoots
    }

    init(
        workspaceKind: ScheduledTaskWorkspaceKind,
        projectPath: String?,
        grantedRootPaths: [String],
        identityAtPath: (String) throws -> TaskWorkspaceFileSystemIdentity
    ) throws {
        if workspaceKind == .project,
           let projectPath {
            projectRoot = ScheduledTaskRootIdentitySnapshot(
                path: projectPath,
                identity: try identityAtPath(projectPath)
            )
        } else {
            projectRoot = nil
        }
        grantedRoots = try grantedRootPaths.map { path in
            ScheduledTaskRootIdentitySnapshot(
                path: path,
                identity: try identityAtPath(path)
            )
        }
    }

    func matchesConfiguration(
        workspaceKind: ScheduledTaskWorkspaceKind,
        projectPath: String?,
        grantedRootPaths: [String]
    ) -> Bool {
        let projectRootMatches: Bool
        switch workspaceKind {
        case .privateWorkspace:
            projectRootMatches = projectRoot == nil && projectPath == nil
        case .project:
            projectRootMatches = projectPath != nil && projectRoot?.path == projectPath
        }
        return projectRootMatches && grantedRoots.map(\.path) == grantedRootPaths
    }

    func identity(for path: String) -> TaskWorkspaceFileSystemIdentity? {
        if projectRoot?.path == path {
            return projectRoot?.identity
        }
        return grantedRoots.first { $0.path == path }?.identity
    }
}

enum ScheduledTaskPreflightOutcome: Equatable, Sendable {
    case ready(ScheduledTaskWorkspaceIdentitySnapshot)
    case invalid(reason: String)
}

typealias ScheduledTaskPreflightValidator = @MainActor @Sendable (
    ScheduledTaskPreflightSnapshot
) async -> ScheduledTaskPreflightOutcome

enum ScheduledTaskClaimResult {
    case claimed(runID: PersistentIdentifier)
    case alreadyClaimed(runID: PersistentIdentifier)
    case skipped(runID: PersistentIdentifier)
    case overlapped(pendingOccurrenceAt: Date)
    case paused(reason: String)
    case changedDuringPreflight
    case activeRunExists
    case inactive
    case notDue
    case definitionNotFound
}

struct ScheduledProjectConfigSnapshot: Equatable, Sendable {
    let path: String
    let baseRef: String?
    let remoteName: String?
}

struct ScheduledTaskClaimRecheck {
    let definitionRevision: Int
    let expectedNextOccurrenceAt: Date?
    let expectedPendingOccurrenceAt: Date?
    let expectedProjectConfiguration: ScheduledProjectConfigSnapshot?
    let occurrenceAt: Date
}

struct ScheduledTaskRunNowRecheck {
    let definitionRevision: Int
    let expectedState: ScheduledTaskState
    let expectedNextOccurrenceAt: Date?
    let expectedPendingOccurrenceAt: Date?
    let expectedProjectConfiguration: ScheduledProjectConfigSnapshot?
}
