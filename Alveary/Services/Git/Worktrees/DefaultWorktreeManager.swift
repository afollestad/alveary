import CryptoKit
import Darwin
import Foundation

actor DefaultWorktreeManager: WorktreeManager {
    typealias DirectoryCreator = @Sendable (_ path: String) throws -> Void
    typealias ProjectConfigLoader = @Sendable (String) async -> AlvearyProjectConfig

    let directoryCreator: DirectoryCreator
    let settingsService: SettingsService
    let shell: ShellRunner
    let projectConfigLoader: ProjectConfigLoader

    init(
        settingsService: SettingsService,
        shell: ShellRunner,
        projectConfigLoader: @escaping ProjectConfigLoader = { projectPath in
            await AlvearyProjectConfig(projectPath: projectPath)
        },
        directoryCreator: @escaping DirectoryCreator = { path in
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: false
            )
        }
    ) {
        self.directoryCreator = directoryCreator
        self.settingsService = settingsService
        self.shell = shell
        self.projectConfigLoader = projectConfigLoader
    }

    func deleteBranch(projectPath: String, branch: String, expectedOID: String) async throws {
        try await deleteBranchValidated(
            projectPath: projectPath,
            branch: branch,
            expectedOID: expectedOID,
            expectedProjectIdentity: nil
        )
    }

    func deleteBranch(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        try await deleteBranchValidated(
            projectPath: projectPath,
            branch: branch,
            expectedOID: expectedOID,
            expectedProjectIdentity: expectedProjectIdentity
        )
    }

    func deleteBranchValidated(
        projectPath: String,
        branch: String,
        expectedOID: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        guard Self.isValidFullObjectID(expectedOID) else {
            throw GitError.commandFailed(
                "Refusing to delete branch \(branch) because its expected object ID is invalid"
            )
        }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["update-ref", "-d", "--", "refs/heads/\(branch)", expectedOID],
                in: projectPath
            )
        } catch {
            try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
            try await reconcileFailedBranchDeletion(
                branch: branch,
                expectedOID: expectedOID,
                projectPath: projectPath,
                expectedProjectIdentity: expectedProjectIdentity,
                failure: error
            )
            return
        }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        guard !result.succeeded else {
            return
        }
        try await reconcileFailedBranchDeletion(
            branch: branch,
            expectedOID: expectedOID,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity,
            failure: Self.makeGitError(from: result)
        )
    }

    func reconcileFailedBranchDeletion(
        branch: String,
        expectedOID: String,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?,
        failure: Error
    ) async throws {
        let currentOID = try await localBranchOID(
            branch,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        guard let currentOID else {
            return
        }
        guard currentOID == expectedOID else {
            throw GitError.commandFailed(
                "Refusing to delete branch \(branch) because its ref changed"
            )
        }
        throw RetryableWorktreeBranchDeletionError(underlying: failure)
    }

    func localBranchOID(
        _ branch: String,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws -> String? {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--hash", "--verify", "refs/heads/\(branch)"],
                in: projectPath
            )
        } catch {
            try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
            throw error
        }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        switch result.exitCode {
        case 0:
            let oid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oid.isEmpty else {
                throw GitError.commandFailed("Git returned an empty object ID for branch \(branch)")
            }
            return oid
        case 1:
            return nil
        default:
            throw Self.makeGitError(from: result)
        }
    }

    func localBranchExists(
        _ branch: String,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws -> Bool {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
                in: projectPath
            )
        } catch {
            try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
            throw error
        }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        switch result.exitCode {
        case 0:
            return true
        case 1:
            return false
        default:
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
    private static func isValidFullObjectID(_ objectID: String) -> Bool {
        let bytes = objectID.utf8
        guard bytes.count == 40 || bytes.count == 64 else {
            return false
        }
        return bytes.allSatisfy { byte in
            switch byte {
            case 48...57, 65...70, 97...102:
                true
            default:
                false
            }
        } && bytes.contains { $0 != 48 }
    }

    static func makeGitError(from result: ShellResult) -> GitError {
        let message = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Git worktree command failed"

        if message.localizedCaseInsensitiveContains("not a git repository") {
            return .notARepository
        }

        if isMissingGitLFSFilterError(message) {
            return .commandFailed(missingGitLFSMessage(originalMessage: message))
        }

        return .commandFailed(message)
    }

    private static func isMissingGitLFSFilterError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("git-lfs") && lowercased.contains("command not found")
    }

    private static func missingGitLFSMessage(originalMessage: String) -> String {
        "Git LFS is required to check out this repository, but git-lfs is not installed or is not available in Alveary's PATH. " +
            "Install Git LFS (for example: brew install git-lfs), run git lfs install, then try again.\n\n" +
            "Original Git error: \(originalMessage)"
    }

    func resolveBaseRef(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws -> String {
        let requestedBaseRef = baseRef ?? "HEAD"
        guard requestedBaseRef != "HEAD" else {
            return "HEAD"
        }

        if let remoteName {
            try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
            let fetchResult = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, requestedBaseRef],
                in: projectPath,
                timeout: .seconds(30)
            )
            try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
            if fetchResult?.succeeded == true {
                return "\(remoteName)/\(requestedBaseRef)"
            }
        }

        return requestedBaseRef
    }

    func resolveWorktreeTarget(
        projectPath: String,
        threadName: String,
        branchPrefix: String,
        worktreesBase: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
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
            let branchExists = try await localBranchExists(
                candidateBranch,
                projectPath: projectPath,
                expectedProjectIdentity: expectedProjectIdentity
            )

            if !pathEntryExists(atPath: candidatePath), !branchExists {
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

    func removeWorktree(
        projectPath: String,
        worktreePath: String,
        identityValidation: WorktreeRemovalIdentityValidation = .unchecked
    ) async throws -> ShellResult {
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)
        var removeResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "remove", "--force", worktreePath],
            in: projectPath
        )
        try requireProjectIdentity(identityValidation.project, at: projectPath)
        try requireWorktreeIdentity(identityValidation, at: worktreePath)

        if !removeResult.succeeded,
           removeResult.stderr.localizedCaseInsensitiveContains("permission") {
            try requireProjectIdentity(identityValidation.project, at: projectPath)
            try requireWorktreeIdentity(identityValidation, at: worktreePath)
            _ = try? await shell.run(executable: "/bin/chmod", args: ["-R", "+w", worktreePath])
            try requireProjectIdentity(identityValidation.project, at: projectPath)
            try requireWorktreeIdentity(identityValidation, at: worktreePath)
            removeResult = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "remove", "--force", worktreePath],
                in: projectPath
            )
            try requireProjectIdentity(identityValidation.project, at: projectPath)
            try requireWorktreeIdentity(identityValidation, at: worktreePath)
        }

        // `git worktree remove` can leave the thread-specific directory itself in place (e.g. when
        // untracked files remain or on certain filesystems), or fail outright because git never
        // registered the worktree (e.g. cancellation during `git worktree add`). Either way, if
        // the thread directory still exists we delete just that directory — never its parent,
        // which holds other threads' worktrees.
        if pathEntryExists(atPath: worktreePath) {
            try requireProjectIdentity(identityValidation.project, at: projectPath)
            try requireWorktreeIdentity(identityValidation, at: worktreePath)
            try FileManager.default.removeItem(atPath: worktreePath)
            guard !pathEntryExists(atPath: worktreePath) else {
                throw GitError.commandFailed("Worktree directory still exists after removal: \(worktreePath)")
            }
        }

        return removeResult
    }

    func pathEntryExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path) ||
            (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
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
