import CryptoKit
import Darwin
import Foundation

actor DefaultWorktreeManager: WorktreeManager {
    private struct WorktreeTarget {
        let path: String
        let branch: String
    }

    private let settingsService: SettingsService
    private let shell: ShellRunner

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
            branchPrefix: settings.branchPrefix
        )
        let resolvedBase = await resolveBaseRef(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName
        )

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

        if settings.pushOnCreate, let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["push", "--set-upstream", remoteName, target.branch],
                in: target.path
            )
        }

        return WorktreeInfo(path: CanonicalPath.normalize(target.path), branch: target.branch)
    }

    func createFromBranch(
        projectPath: String,
        threadName: String,
        branch: String,
        remoteName: String?
    ) async throws -> WorktreeInfo {
        let worktreePath = resolveUniqueWorktreePath(projectPath: projectPath, threadName: threadName)

        if let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, branch],
                in: projectPath,
                timeout: .seconds(30)
            )
        }

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

private extension DefaultWorktreeManager {
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
        branchPrefix: String
    ) async throws -> WorktreeTarget {
        let candidateBase = makeCandidateBase(projectPath: projectPath, threadName: threadName)

        for suffix in 0..<10_000 {
            let candidateName = candidateName(baseName: candidateBase.baseName, suffix: suffix)
            let candidatePath = candidateBase.worktreesDirectory.appendingPathComponent(candidateName).path
            let candidateBranch = "\(branchPrefix)/\(candidateName)"
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

    func resolveUniqueWorktreePath(projectPath: String, threadName: String) -> String {
        let candidateBase = makeCandidateBase(projectPath: projectPath, threadName: threadName)

        for suffix in 0..<10_000 {
            let candidateName = candidateName(baseName: candidateBase.baseName, suffix: suffix)
            let candidatePath = candidateBase.worktreesDirectory.appendingPathComponent(candidateName).path
            if !FileManager.default.fileExists(atPath: candidatePath) {
                return candidatePath
            }
        }

        return candidateBase.worktreesDirectory.appendingPathComponent(candidateBase.baseName).path
    }

    func makeCandidateBase(projectPath: String, threadName: String) -> (baseName: String, worktreesDirectory: URL) {
        let slug = slugify(threadName)
        let hash = shortHash(threadName)
        let worktreesDirectory = URL(fileURLWithPath: projectPath)
            .deletingLastPathComponent()
            .appendingPathComponent("worktrees")
            .appendingPathComponent(projectNamespace(for: projectPath))

        return (baseName: "\(slug)-\(hash)", worktreesDirectory: worktreesDirectory)
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

    func runTeardownScriptIfNeeded(
        projectPath: String,
        worktreePath: String,
        branch: String?
    ) async {
        let config = await SkepProjectConfig(projectPath: projectPath)
        guard let teardownScript = config.teardownScript else {
            return
        }

        _ = try? await shell.run(
            executable: "/bin/sh",
            args: ["-c", teardownScript],
            in: worktreePath,
            environment: buildLifecycleScriptEnvironment(
                projectPath: projectPath,
                worktreePath: worktreePath,
                threadName: URL(fileURLWithPath: worktreePath).lastPathComponent,
                branch: branch
            ),
            timeout: .seconds(60)
        )
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

        return removeResult
    }

    func runSetupScript(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        config: SkepProjectConfig
    ) async -> String? {
        guard let setupScript = config.setupScript else {
            return nil
        }

        do {
            let result = try await shell.run(
                executable: "/bin/sh",
                args: ["-c", setupScript],
                in: worktreePath,
                environment: buildLifecycleScriptEnvironment(
                    projectPath: projectPath,
                    worktreePath: worktreePath,
                    threadName: threadName,
                    branch: branch
                ),
                timeout: .seconds(config.setupTimeoutSeconds ?? 300)
            )
            return result.succeeded
                ? nil
                : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return error.localizedDescription
        }
    }

    func cleanupFailedSetup(
        projectPath: String,
        worktreePath: String,
        rollbackBranch: String?
    ) async throws -> Bool {
        let removeResult = try? await removeWorktree(projectPath: projectPath, worktreePath: worktreePath)
        let rollbackBranchDeleteFailed = try await rollbackBranchDeleteFailed(
            projectPath: projectPath,
            rollbackBranch: rollbackBranch
        )
        return removeResult?.succeeded != true || rollbackBranchDeleteFailed
    }

    func rollbackBranchDeleteFailed(projectPath: String, rollbackBranch: String?) async throws -> Bool {
        guard let rollbackBranch else {
            return false
        }

        let deleteResult = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["branch", "-D", rollbackBranch],
            in: projectPath
        )
        return deleteResult?.succeeded == false
    }

    func postCreateSetup(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        rollbackBranch: String?
    ) async throws {
        let config = await SkepProjectConfig(projectPath: projectPath)
        try preserveFiles(from: projectPath, to: worktreePath, patterns: config.preservePatterns)

        guard config.setupScript != nil else { return }

        let failureMessage = await runSetupScript(
            projectPath: projectPath,
            worktreePath: worktreePath,
            threadName: threadName,
            branch: branch,
            config: config
        )
        guard let failureMessage else {
            return
        }

        if try await cleanupFailedSetup(
            projectPath: projectPath,
            worktreePath: worktreePath,
            rollbackBranch: rollbackBranch
        ) {
            throw GitError.commandFailed(
                "Setup script failed: \(failureMessage). Cleanup also failed for worktree \(worktreePath)."
            )
        }

        throw GitError.commandFailed("Setup script failed: \(failureMessage)")
    }

    func buildLifecycleScriptEnvironment(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String?
    ) -> [String: String] {
        var environment: [String: String] = [
            "SKEP_THREAD_NAME": threadName,
            "SKEP_PROJECT_PATH": projectPath,
            "SKEP_WORKTREE_PATH": worktreePath,
            "SKEP_PORT_SEED": shortHash(branch ?? worktreePath)
        ]

        if let branch {
            environment["SKEP_BRANCH_NAME"] = branch
        }

        return environment
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

    func preserveFiles(from source: String, to destination: String, patterns configPatterns: [String]?) throws {
        let patterns = configPatterns ?? [".env", ".env.local", ".env.development"]
        let sourceURL = URL(fileURLWithPath: source)
        let destinationURL = URL(fileURLWithPath: destination)
        let fileManager = FileManager.default

        for pattern in patterns {
            let fullPattern = sourceURL.appendingPathComponent(pattern).path
            var globResult = glob_t()
            defer { globfree(&globResult) }

            guard glob(fullPattern, 0, nil, &globResult) == 0 else {
                continue
            }

            for index in 0..<Int(globResult.gl_pathc) {
                guard let matchPointer = globResult.gl_pathv[index],
                      let matchedPath = String(validatingCString: matchPointer) else {
                    continue
                }

                let relativePath = String(matchedPath.dropFirst(sourceURL.path.count + 1))
                let destinationPath = destinationURL.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: destinationPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationPath.path) {
                    try? fileManager.removeItem(at: destinationPath)
                }
                try? fileManager.copyItem(atPath: matchedPath, toPath: destinationPath.path)
            }
        }
    }

    func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst(9))
            } else if line.hasPrefix("branch refs/heads/") {
                currentBranch = String(line.dropFirst(18))
            } else if line.isEmpty {
                if let currentPath, let currentBranch {
                    worktrees.append(WorktreeInfo(path: currentPath, branch: currentBranch))
                }
                currentPath = nil
                currentBranch = nil
            }
        }

        if let currentPath, let currentBranch {
            worktrees.append(WorktreeInfo(path: currentPath, branch: currentBranch))
        }

        return worktrees
    }
}
