import CryptoKit
import Darwin
import Foundation

actor DefaultWorktreeManager: WorktreeManager {
    private struct WorktreeTarget {
        let path: String
        let branch: String
    }

    let settingsService: SettingsService
    let shell: ShellRunner

    init(settingsService: SettingsService, shell: ShellRunner) {
        self.settingsService = settingsService
        self.shell = shell
    }

    func create(
        projectPath: String,
        threadName: String,
        baseRef: String?,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        let settings = await MainActor.run { settingsService.current }
        let target = try await resolveWorktreeTarget(
            projectPath: projectPath,
            threadName: threadName,
            branchPrefix: settings.branchPrefix,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        let resolvedBase = await resolveBaseRef(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName
        )

        try ensureWorktreeParentDirectoryExists(for: target.path)

        // `git worktree add` itself can leave partial state — e.g. an empty target directory — if
        // it is cancelled mid-run (Task cancellation sends SIGTERM to the git process). Wrap the
        // whole add + post-setup sequence in cleanup so any failure, including interruption during
        // `git worktree add`, removes the partial directory and rollback branch before rethrowing.
        do {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "add", "--no-track", "-b", target.branch, target.path, resolvedBase],
                in: projectPath
            )
            guard result.succeeded else {
                throw Self.makeGitError(from: result)
            }

            try await postCreateSetup(
                projectPath: projectPath,
                worktreePath: target.path,
                threadName: threadName,
                branch: target.branch,
                rollbackBranch: target.branch
            )

            return WorktreeInfo(path: CanonicalPath.normalize(target.path), branch: target.branch)
        } catch {
            await detachedCleanupAfterFailedCreate(
                projectPath: projectPath,
                worktreePath: target.path,
                rollbackBranch: target.branch
            )
            throw error
        }
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        let settings = await MainActor.run { settingsService.current }
        let worktreePath = resolveUniqueWorktreePath(
            projectPath: projectPath,
            threadName: threadName,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )

        if let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, branch],
                in: projectPath,
                timeout: .seconds(30)
            )
        }

        try ensureWorktreeParentDirectoryExists(for: worktreePath)

        // See the matching comment in `create()` — interrupting `git worktree add` can leave the
        // target directory behind, so wrap the add + post-setup in cleanup. `rollbackBranch` is nil
        // because the branch already existed before this call.
        do {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "add", worktreePath, branch],
                in: projectPath
            )
            guard result.succeeded else {
                throw Self.makeGitError(from: result)
            }

            try await postCreateSetup(
                projectPath: projectPath,
                worktreePath: worktreePath,
                threadName: threadName,
                branch: branch,
                rollbackBranch: nil
            )

            return WorktreeInfo(path: CanonicalPath.normalize(worktreePath), branch: branch)
        } catch {
            await detachedCleanupAfterFailedCreate(
                projectPath: projectPath,
                worktreePath: worktreePath,
                rollbackBranch: nil
            )
            throw error
        }
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        let listResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: projectPath
        )
        guard listResult.succeeded else {
            throw Self.makeGitError(from: listResult)
        }

        let canonicalProjectPath = CanonicalPath.normalize(projectPath)
        let canonicalWorktreePath = CanonicalPath.normalize(worktreePath)
        let worktrees = parseWorktreeList(listResult.stdout)
        let isWorktree = worktrees.contains { CanonicalPath.normalize($0.path) == canonicalWorktreePath }
        let isMainRepository = canonicalProjectPath == canonicalWorktreePath

        guard isWorktree, !isMainRepository else {
            throw GitError.commandFailed("Refusing to remove: \(worktreePath) is not a removable worktree")
        }

        await runTeardownScriptIfNeeded(projectPath: projectPath, worktreePath: worktreePath, branch: branch)

        let removeResult = try await removeWorktree(projectPath: projectPath, worktreePath: worktreePath)
        guard removeResult.succeeded else {
            throw Self.makeGitError(from: removeResult)
        }

        if let branch {
            try await deleteBranch(projectPath: projectPath, branch: branch)
        }
    }

    func deleteBranch(projectPath: String, branch: String) async throws {
        let branchExists = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            in: projectPath
        )
        guard branchExists?.succeeded == true else {
            return
        }

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["branch", "-D", branch],
            in: projectPath
        )
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
    }

    func list(projectPath: String) async throws -> [WorktreeInfo] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: projectPath
        )
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
        return parseWorktreeList(result.stdout)
    }
}

extension DefaultWorktreeManager {
    static func makeGitError(from result: ShellResult) -> GitError {
        let message = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Git worktree command failed"

        if message.localizedCaseInsensitiveContains("not a git repository") {
            return .notARepository
        }

        return .commandFailed(message)
    }

    func resolveBaseRef(projectPath: String, baseRef: String?, remoteName: String?) async -> String {
        let requestedBaseRef = baseRef ?? "HEAD"
        guard requestedBaseRef != "HEAD" else {
            return "HEAD"
        }

        if let remoteName {
            let fetchResult = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, requestedBaseRef],
                in: projectPath,
                timeout: .seconds(30)
            )
            if fetchResult?.succeeded == true {
                return "\(remoteName)/\(requestedBaseRef)"
            }
        }

        return requestedBaseRef
    }

    private func resolveWorktreeTarget(
        projectPath: String,
        threadName: String,
        branchPrefix: String,
        worktreesBase: String
    ) async throws -> WorktreeTarget {
        let candidateBase = makeCandidateBase(
            projectPath: projectPath,
            threadName: threadName,
            worktreesBase: worktreesBase
        )

        for suffix in 0..<10_000 {
            let candidateName = candidateName(baseName: candidateBase.baseName, suffix: suffix)
            let candidatePath = candidateBase.worktreesDirectory.appendingPathComponent(candidateName).path
            let candidateBranch = branchPrefix + candidateName
            let branchExists = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--verify", "--quiet", "refs/heads/\(candidateBranch)"],
                in: projectPath
            )

            if !FileManager.default.fileExists(atPath: candidatePath), branchExists?.succeeded != true {
                return WorktreeTarget(path: candidatePath, branch: candidateBranch)
            }
        }

        throw GitError.commandFailed("Unable to find a unique worktree target for \(threadName)")
    }

    func resolveUniqueWorktreePath(projectPath: String, threadName: String, worktreesBase: String) -> String {
        let candidateBase = makeCandidateBase(
            projectPath: projectPath,
            threadName: threadName,
            worktreesBase: worktreesBase
        )

        for suffix in 0..<10_000 {
            let candidateName = candidateName(baseName: candidateBase.baseName, suffix: suffix)
            let candidatePath = candidateBase.worktreesDirectory.appendingPathComponent(candidateName).path
            if !FileManager.default.fileExists(atPath: candidatePath) {
                return candidatePath
            }
        }

        return candidateBase.worktreesDirectory.appendingPathComponent(candidateBase.baseName).path
    }

    func makeCandidateBase(
        projectPath: String,
        threadName: String,
        worktreesBase: String
    ) -> (baseName: String, worktreesDirectory: URL) {
        let slug = slugify(threadName)
        let hash = shortHash(threadName)
        let worktreesDirectory = projectWorktreesDirectory(for: projectPath, worktreesBase: worktreesBase)

        return (baseName: "\(slug)-\(hash)", worktreesDirectory: worktreesDirectory)
    }

    func ensureWorktreeParentDirectoryExists(for worktreePath: String) throws {
        let parent = URL(fileURLWithPath: worktreePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    func candidateName(baseName: String, suffix: Int) -> String {
        suffix == 0 ? baseName : "\(baseName)-\(suffix + 1)"
    }

    func projectNamespace(for projectPath: String) -> String {
        let canonicalProjectPath = CanonicalPath.normalize(projectPath)
        let projectName = URL(fileURLWithPath: canonicalProjectPath).lastPathComponent
        let digest = SHA256.hash(data: Data(canonicalProjectPath.utf8))
        let hash = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(slugify(projectName))-\(hash)"
    }

    func removeWorktree(projectPath: String, worktreePath: String) async throws -> ShellResult {
        var removeResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "remove", "--force", worktreePath],
            in: projectPath
        )

        if !removeResult.succeeded,
           removeResult.stderr.localizedCaseInsensitiveContains("permission") {
            _ = try? await shell.run(executable: "/bin/chmod", args: ["-R", "+w", worktreePath])
            removeResult = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "remove", "--force", worktreePath],
                in: projectPath
            )
        }

        // `git worktree remove` can leave the thread-specific directory itself in place (e.g. when
        // untracked files remain or on certain filesystems), or fail outright because git never
        // registered the worktree (e.g. cancellation during `git worktree add`). Either way, if
        // the thread directory still exists we delete just that directory — never its parent,
        // which holds other threads' worktrees.
        if FileManager.default.fileExists(atPath: worktreePath) {
            try? FileManager.default.removeItem(atPath: worktreePath)
        }

        return removeResult
    }

    func slugify(_ value: String) -> String {
        let slug = value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        guard !slug.isEmpty else {
            return "thread"
        }
        return String(slug.prefix(50))
    }

    func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hexDigest = digest.map { String(format: "%02x", $0) }.joined()
        return String(hexDigest.prefix(3))
    }

}
