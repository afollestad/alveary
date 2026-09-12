import AgentCLIKit
import Foundation
import SwiftData

extension ConversationViewModel {
    func createInitialWorkingDirectory(
        for thread: AgentThread,
        project _: Project?,
        message: String
    ) async throws -> String {
        guard let snapshot = thread.workspaceSnapshot,
              let directory = thread.primaryWorkingDirectory else {
            throw WorkspaceFolderError.invalidSnapshot
        }
        guard thread.effectiveMode == .project, thread.useWorktree else { return directory }
        guard let source = snapshot.primarySource else { throw WorkspaceFolderError.invalidSnapshot }
        guard source.isGitRepository else {
            thread.useWorktree = false
            try modelContext.save()
            return directory
        }

        let threadID = thread.persistentModelID
        let worktreeSlug = AgentSessionPreviewGenerator.preview(fromInitialPrompt: message) ?? thread.name
        setupPhase = .creatingWorktree
        let info = try await worktreeManager.create(
            projectPath: source.path, threadName: worktreeSlug, baseRef: source.baseRef, remoteName: source.remoteName
        )
        do {
            try Task.checkCancellation()
            guard let liveThread = modelContext.resolveThread(id: threadID), liveThread.workspaceSnapshot == snapshot else {
                throw AgentError.spawnFailed("The thread workspace changed during setup")
            }
            liveThread.worktreePath = info.path
            liveThread.branch = info.branch
            try modelContext.save()
            return info.path
        } catch {
            await rollbackCreatedWorktree(info, sourcePath: source.path, threadID: threadID)
            setupPhase = nil
            throw error
        }
    }

    private func rollbackCreatedWorktree(_ info: WorktreeInfo, sourcePath: String, threadID: PersistentIdentifier) async {
        do {
            let manager = worktreeManager
            let cleanup = Task { try await manager.remove(projectPath: sourcePath, worktreePath: info.path, branch: info.branch) }
            try await cleanup.value
            if let thread = modelContext.resolveThread(id: threadID), thread.worktreePath == info.path {
                thread.worktreePath = nil
                thread.branch = nil
                try modelContext.save()
            }
        } catch {
            // Retain exact provenance when cleanup fails, including cancellation before the first metadata save.
            if let thread = modelContext.resolveThread(id: threadID), thread.worktreePath == nil || thread.worktreePath == info.path {
                thread.worktreePath = info.path
                thread.branch = info.branch
                preserveWorktreeAfterFailedRollback(cleanupError: error, thread: thread)
            } else {
                state.lastTurnError = "Worktree rollback failed at \(info.path): \(error.localizedDescription)"
            }
        }
    }
}
