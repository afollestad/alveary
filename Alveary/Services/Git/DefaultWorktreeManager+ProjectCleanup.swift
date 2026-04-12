import Foundation

extension DefaultWorktreeManager {
    func removeAll(projectPath: String) async throws {
        guard directoryExists(at: projectPath) else {
            try removeProjectWorktreesDirectory(projectPath: projectPath)
            return
        }

        let canonicalProjectPath = CanonicalPath.normalize(projectPath)

        do {
            let worktrees = try await list(projectPath: projectPath)
            for worktree in worktrees where CanonicalPath.normalize(worktree.path) != canonicalProjectPath {
                await runTeardownScriptIfNeeded(
                    projectPath: projectPath,
                    worktreePath: worktree.path,
                    branch: worktree.branch
                )

                let removeResult = try await removeWorktree(
                    projectPath: projectPath,
                    worktreePath: worktree.path
                )
                guard removeResult.succeeded else {
                    throw Self.makeGitError(from: removeResult)
                }

                try await deleteBranch(projectPath: projectPath, branch: worktree.branch)
            }
        } catch let error as GitError {
            guard error == .notARepository else {
                throw error
            }
        }

        try removeProjectWorktreesDirectory(projectPath: projectPath)
    }
}

extension DefaultWorktreeManager {
    func projectWorktreesDirectory(for projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .deletingLastPathComponent()
            .appendingPathComponent("worktrees")
            .appendingPathComponent(projectNamespace(for: projectPath))
    }

    func directoryExists(at path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(
            atPath: path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    func removeProjectWorktreesDirectory(projectPath: String) throws {
        let directory = projectWorktreesDirectory(for: projectPath)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }

        try FileManager.default.removeItem(at: directory)
    }
}
