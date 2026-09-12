import Foundation

struct DiffViewerSwitchTarget: Equatable {
    let projectPath: String
    let worktreePath: String?
    let directory: String
    let baseRef: String
    let remoteName: String?
    let conversationIds: Set<String>
    var sourceDirectory: String?

    var path: String { directory }

    var workspaceTarget: DiffWorkspaceTarget {
        DiffWorkspaceTarget(
            projectPath: projectPath,
            worktreePath: worktreePath,
            directory: directory,
            baseRef: baseRef,
            remoteName: remoteName,
            sourceDirectory: sourceDirectory
        )
    }
}

extension DiffViewerSwitchTarget {
    static func forThread(_ thread: AgentThread, candidateConversationIDs: Set<String>? = nil) -> DiffViewerSwitchTarget? {
        guard let folder = thread.workspaceFolderTargets.first(where: \.isPrimary) else { return nil }
        return forFolder(folder, conversationIDs: candidateConversationIDs ?? Set(thread.conversations.map(\.id)))
    }

    static func forFolder(_ folder: WorkspaceFolderTarget, conversationIDs: Set<String> = []) -> DiffViewerSwitchTarget {
        DiffViewerSwitchTarget(
            projectPath: folder.source.path,
            worktreePath: folder.directory == folder.source.path ? nil : folder.directory,
            directory: folder.directory,
            baseRef: folder.baseRef ?? "main",
            remoteName: folder.remoteName,
            conversationIds: conversationIDs
        )
    }

    static func forProject(
        _ project: Project,
        candidateThreads: [AgentThread]? = nil,
        candidateConversationIDs: Set<String>? = nil
    ) -> DiffViewerSwitchTarget? {
        guard let folder = project.workspaceFolderTargets.first(where: \.isPrimary) else { return nil }
        let threads = candidateThreads ?? project.threads
        let conversationIDs = candidateConversationIDs ?? Set(threads.filter {
            $0.archivedAt == nil && $0.workspaceFolderTargets.contains { $0.directory == folder.directory }
        }.flatMap { $0.conversations.map(\.id) })
        return forFolder(folder, conversationIDs: conversationIDs)
    }
}

/// Git works from the repository root while grants, settings, and terminals keep their literal folder.
extension DiffViewerSwitchTarget {
    func resolvingRepositoryDirectory(using gitService: GitService) async throws -> DiffViewerSwitchTarget {
        let root = try await gitService.repositoryRoot(in: directory) ?? directory
        return DiffViewerSwitchTarget(
            projectPath: projectPath,
            worktreePath: worktreePath,
            directory: root,
            baseRef: baseRef,
            remoteName: remoteName,
            conversationIds: conversationIds,
            sourceDirectory: sourceDirectory ?? (root == directory ? nil : directory)
        )
    }
}
