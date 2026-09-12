import Foundation
import SwiftData

/// Older unversioned schemas first migrate additively into this bridge. Its legacy columns remain
/// available while IDs, folder memberships and workspace snapshots are populated in one save.
enum ProjectWorkspaceBridgeSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Project.self, ProjectFolder.self, AgentThread.self, SidebarSection.self, Conversation.self,
         ConversationEventRecord.self, ScheduledTask.self, ScheduledTaskRun.self, ScheduledTaskProposal.self]
    }

    static func backfill(in context: ModelContext) throws {
        try backfillProjects(in: context)
        try backfillThreads(in: context)
        try backfillSchedules(in: context)
        try backfillRuns(in: context)
        try context.save()
    }

    private static func backfillProjects(in context: ModelContext) throws {
        for project in try context.fetch(FetchDescriptor<Project>()) {
            if project.id == nil { project.id = UUID().uuidString }
            if project.folders.isEmpty {
                let folder = ProjectFolder()
                folder.id = UUID().uuidString
                folder.path = project.path
                folder.gitRemote = project.gitRemote
                folder.remoteName = project.remoteName
                folder.gitBranch = project.gitBranch
                folder.baseRef = project.baseRef
                folder.githubRepository = project.githubRepository
                folder.githubConnected = project.githubConnected
                folder.project = project
                project.folders = [folder]
                project.primaryFolderID = folder.id
                context.insert(folder)
            }
        }
    }

    private static func backfillThreads(in context: ModelContext) throws {
        let sources = Dictionary(try context.fetch(FetchDescriptor<Project>()).map { ($0.path, $0) },
                                 uniquingKeysWith: { first, _ in first })
        for thread in try context.fetch(FetchDescriptor<AgentThread>()) where thread.workspaceSnapshotJSON == nil {
            let source = thread.modeRawValue == "task" ? thread.taskSourceProjectPath : thread.project?.path
            var workspace = snapshot(sourcePath: source, project: source.flatMap { sources[$0] }, grants: thread.taskGrantedRoots)
            if thread.taskWorkspaceOwnershipStrategyRawValue == "projectWorktreeOwned", workspace.primarySource?.isGitRepository == false {
                workspace.primarySource?.gitRepositoryDetected = true
            }
            thread.workspaceSnapshotJSON = workspace.encoded
        }
    }

    private static func backfillSchedules(in context: ModelContext) throws {
        for schedule in try context.fetch(FetchDescriptor<ScheduledTask>()) where schedule.workspaceSnapshotJSON == nil {
            let target = schedule.targetThread ?? schedule.reusedThread
            if let snapshot = target?.workspaceSnapshotJSON {
                schedule.workspaceSnapshotJSON = snapshot
                if let workspace = WorkspaceSnapshot.decode(snapshot) {
                    schedule.grantedRoots = workspace.grants.map(\.path)
                    if schedule.destinationRawValue != ScheduledTaskDestination.existingThread.rawValue {
                        schedule.workspaceKindRawValue = workspace.primarySource == nil ? "privateWorkspace" : "project"
                    }
                }
            } else {
                schedule.workspaceSnapshotJSON = snapshot(
                    sourcePath: schedule.workspaceKindRawValue == "project" ? schedule.project?.path : nil,
                    project: schedule.project, grants: schedule.grantedRoots
                ).encoded
            }
        }
    }

    private static func backfillRuns(in context: ModelContext) throws {
        for run in try context.fetch(FetchDescriptor<ScheduledTaskRun>()) where run.workspaceSnapshotJSON == nil {
            let target = run.targetThread ?? run.thread
            let savedWorkspace = WorkspaceSnapshot.decode(target?.workspaceSnapshotJSON)
            let existingTarget = run.destinationRawValueSnapshot == ScheduledTaskDestination.existingThread.rawValue
            var source = existingTarget ? savedWorkspace?.primarySource : nil
            if source == nil, let path = run.projectPathSnapshot {
                source = savedWorkspace?.sourceFolders.first { $0.path == path } ?? SourceFolderSnapshot(path: path)
            }
            if let baseRef = run.projectBaseRefSnapshot { source?.baseRef = baseRef }
            if let remoteName = run.projectRemoteNameSnapshot { source?.remoteName = remoteName }
            run.workspaceSnapshotJSON = WorkspaceSnapshot(
                primarySource: source, grants: run.grantedRootsSnapshot.map { path in
                    savedWorkspace?.sourceFolders.first { $0.path == path } ?? SourceFolderSnapshot(path: path)
                },
                rootsExplicitlyManaged: !run.grantedRootsSnapshot.isEmpty
            ).encoded
            run.projectIDSnapshot = target?.project?.id ?? run.scheduledTask?.project?.id
        }
    }

    private static func snapshot(sourcePath: String?, project: Project?, grants: [String]) -> WorkspaceSnapshot {
        let source = sourcePath.map { path in
            SourceFolderSnapshot(
                path: path, gitRemote: project?.path == path ? project?.gitRemote : nil,
                remoteName: project?.path == path ? project?.remoteName : nil,
                gitBranch: project?.path == path ? project?.gitBranch : nil,
                baseRef: project?.path == path ? project?.baseRef : nil,
                githubRepository: project?.path == path ? project?.githubRepository : nil,
                githubConnected: project?.path == path ? project?.githubConnected ?? false : false
            )
        }
        return WorkspaceSnapshot(
            primarySource: source, grants: grants.map { SourceFolderSnapshot(path: $0) }, rootsExplicitlyManaged: !grants.isEmpty
        )
    }
}

enum AlvearySchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Project.self, ProjectFolder.self, AgentThread.self, SidebarSection.self, Conversation.self,
         ConversationEventRecord.self, ScheduledTask.self, ScheduledTaskRun.self, ScheduledTaskProposal.self]
    }
}

enum ProjectWorkspaceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ProjectWorkspaceBridgeSchema.self, AlvearySchema.self] }
    static var stages: [MigrationStage] {
        [.custom(
            fromVersion: ProjectWorkspaceBridgeSchema.self, toVersion: AlvearySchema.self,
            willMigrate: { context in try ProjectWorkspaceBridgeSchema.backfill(in: context) }, didMigrate: nil
        )]
    }
}
