import Foundation

extension DefaultWorktreeManager {
    func removeAll(projectPath: String) async throws {
        let worktreesBase = await MainActor.run { settingsService.current.expandedWorktreesBaseDirectory }

        guard directoryExists(at: projectPath) else {
            try removeProjectWorktreesDirectory(projectPath: projectPath, worktreesBase: worktreesBase)
            return
        }

        let canonicalProjectPath = CanonicalPath.normalize(projectPath)

        do {
            let worktrees = try await list(projectPath: projectPath)
            for worktree in worktrees where CanonicalPath.normalize(worktree.path) != canonicalProjectPath {
                try? await runTeardownScriptIfNeeded(
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

                if let headOID = worktree.headOID {
                    try await deleteBranch(
                        projectPath: projectPath,
                        branch: worktree.branch,
                        expectedOID: headOID
                    )
                }
            }
        } catch let error as GitError {
            guard error == .notARepository else {
                throw error
            }
        }

        try removeProjectWorktreesDirectory(projectPath: projectPath, worktreesBase: worktreesBase)
    }
}

extension DefaultWorktreeManager {
    func projectWorktreesDirectory(for projectPath: String, worktreesBase: String) -> URL {
        URL(fileURLWithPath: worktreesBase)
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

    func removeProjectWorktreesDirectory(projectPath: String, worktreesBase: String) throws {
        let directory = projectWorktreesDirectory(for: projectPath, worktreesBase: worktreesBase)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }

        try FileManager.default.removeItem(at: directory)
    }
}
