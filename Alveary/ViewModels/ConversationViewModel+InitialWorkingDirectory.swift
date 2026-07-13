import AgentCLIKit
import Foundation

extension ConversationViewModel {
    func createInitialWorkingDirectory(
        for thread: AgentThread,
        project: Project?,
        message: String
    ) async throws -> String {
        if thread.mode == .task {
            guard let workingDirectory = thread.primaryWorkingDirectory else {
                throw AgentError.spawnFailed("Cannot start task: no workspace is available")
            }
            return workingDirectory
        }

        guard let project else {
            throw AgentError.spawnFailed("No project associated with this thread")
        }
        guard thread.useWorktree else {
            return project.path
        }

        guard project.isGitRepository else {
            thread.useWorktree = false
            try modelContext.save()
            return project.path
        }

        setupPhase = .creatingWorktree
        let worktreeSlug = AgentSessionPreviewGenerator.preview(fromInitialPrompt: message) ?? thread.name

        do {
            let info = try await worktreeManager.create(
                projectPath: project.path,
                threadName: worktreeSlug,
                baseRef: project.baseRef,
                remoteName: project.remoteName
            )
            thread.worktreePath = info.path
            thread.branch = info.branch
            try modelContext.save()
            return info.path
        } catch {
            await rollbackFailedWorktreeCreation(for: thread, project: project)
            setupPhase = nil
            throw error
        }
    }

    private func rollbackFailedWorktreeCreation(for thread: AgentThread, project: Project) async {
        guard let path = thread.worktreePath else {
            return
        }

        do {
            try await worktreeManager.remove(
                projectPath: project.path,
                worktreePath: path,
                branch: thread.branch
            )
            thread.worktreePath = nil
            thread.branch = nil
            try modelContext.save()
        } catch {
            state.lastTurnError =
                "Initial worktree setup failed and rollback cleanup/metadata clear also failed: " +
                error.localizedDescription
        }
    }
}
