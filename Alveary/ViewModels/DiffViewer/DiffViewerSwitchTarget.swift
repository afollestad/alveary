import Foundation

struct DiffViewerSwitchTarget: Equatable {
    let projectPath: String
    let worktreePath: String?
    let directory: String
    let baseRef: String
    let remoteName: String?
    let conversationIds: Set<String>

    var path: String { directory }

    var workspaceTarget: DiffWorkspaceTarget {
        DiffWorkspaceTarget(
            projectPath: projectPath,
            worktreePath: worktreePath,
            directory: directory,
            baseRef: baseRef,
            remoteName: remoteName
        )
    }
}

extension DiffViewerSwitchTarget {
    static func forThread(_ thread: AgentThread, candidateConversationIDs: Set<String>? = nil) -> DiffViewerSwitchTarget? {
        guard let directory = thread.primaryWorkingDirectory else {
            return nil
        }
        let projectPath = thread.sourceProjectCleanupPath ?? directory
        let taskWorktreePath = thread.taskWorkspaceDescriptor?.ownershipStrategy == .projectWorktreeOwned
            ? thread.taskWorkspaceDescriptor?.primaryRoot
            : nil
        let resolvedWorktreePath = thread.effectiveMode == .project ? thread.worktreePath : taskWorktreePath
        let worktreePath = resolvedWorktreePath == projectPath ? nil : resolvedWorktreePath
        return DiffViewerSwitchTarget(
            projectPath: projectPath,
            worktreePath: worktreePath,
            directory: directory,
            baseRef: thread.project?.baseRef ?? "main",
            remoteName: thread.project?.remoteName,
            conversationIds: candidateConversationIDs ?? Set(thread.conversations.map(\.id))
        )
    }

    // Only threads operating directly on the project path — i.e. those without
    // a worktree — mutate the project directory on disk, so scope agent-status
    // refreshes to their conversations. Filesystem changes coming from other
    // sources (worktree merges, external git commands) are still picked up by
    // the diff viewer's FSEvents path.
    static func forProject(
        _ project: Project,
        candidateThreads: [AgentThread]? = nil,
        candidateConversationIDs: Set<String>? = nil
    ) -> DiffViewerSwitchTarget {
        let threads = candidateThreads ?? project.threads
        let conversationIds = candidateConversationIDs ?? Set(
            threads
                .filter {
                    $0.effectiveMode == .project &&
                        $0.archivedAt == nil &&
                        ($0.worktreePath == nil || $0.worktreePath == project.path)
                }
                .flatMap(\.conversations)
                .map(\.id)
        )
        return DiffViewerSwitchTarget(
            projectPath: project.path,
            worktreePath: nil,
            directory: project.path,
            baseRef: project.baseRef ?? "main",
            remoteName: project.remoteName,
            conversationIds: conversationIds
        )
    }
}
