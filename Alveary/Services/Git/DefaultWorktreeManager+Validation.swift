import Foundation

extension DefaultWorktreeManager {
    func validateCreatedWorktreeTarget(
        _ prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        guard prepared.expectedProjectIdentity != nil else {
            return
        }
        try validateWorktreeTargetParent(
            targetPath: prepared.target.path,
            projectPath: prepared.projectPath,
            worktreesBase: prepared.worktreesBase,
            expectedParentIdentity: prepared.expectedTargetParentIdentity
        )
        try requireCreationIdentities(
            WorktreeCreationIdentityValidation(
                project: prepared.expectedProjectIdentity,
                worktree: worktreeIdentity
            ),
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
    }

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?
    ) async throws {
        try await validateCreation(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: nil
        )
    }

    func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity
    ) async throws {
        try await validateCreation(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: Optional(expectedProjectIdentity)
        )
    }

    private func validateCreation(
        projectPath: String,
        baseRef: String?,
        remoteName: String?,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let settings = await MainActor.run { settingsService.current }
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        try validateWorktreeDestination(
            projectPath: projectPath,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
        try await validateBranchPrefix(
            settings.branchPrefix,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        let resolvedBase = try await resolveBaseRef(
            projectPath: projectPath,
            baseRef: baseRef,
            remoteName: remoteName,
            expectedProjectIdentity: expectedProjectIdentity
        )
        try await validateResolvedBase(
            resolvedBase,
            projectPath: projectPath,
            expectedProjectIdentity: expectedProjectIdentity
        )
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        try validateWorktreeDestination(
            projectPath: projectPath,
            worktreesBase: settings.expandedWorktreesBaseDirectory
        )
    }

    func validateResolvedBase(
        _ resolvedBase: String,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--verify", "\(resolvedBase)^{commit}"],
            in: projectPath
        )
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
    }
}

extension DefaultWorktreeManager {
    func validateWorktreeDestination(
        projectPath: String,
        worktreesBase: String
    ) throws {
        try rejectNoncanonicalWorktreeDestination(
            at: worktreesBase,
            reporting: worktreesBase
        )
        try rejectWorktreeDestinationSymlink(at: worktreesBase)
        var candidate = projectWorktreesDirectory(
            for: projectPath,
            worktreesBase: worktreesBase
        )
        let fileManager = FileManager.default

        while true {
            try rejectNoncanonicalWorktreeDestination(
                at: candidate.path,
                reporting: worktreesBase
            )
            try rejectWorktreeDestinationSymlink(at: candidate.path)
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw GitError.commandFailed(
                        "The configured worktrees path is not a directory: \(candidate.path)"
                    )
                }
                guard fileManager.isWritableFile(atPath: candidate.path),
                      fileManager.isExecutableFile(atPath: candidate.path) else {
                    throw GitError.commandFailed(
                        "The configured worktrees path is not writable: \(candidate.path)"
                    )
                }
                return
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                throw GitError.commandFailed(
                    "The configured worktrees path cannot be created: \(worktreesBase)"
                )
            }
            candidate = parent
        }
    }

    func validateBranchPrefix(
        _ branchPrefix: String,
        projectPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws {
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        let candidateBranch = branchPrefix + "scheduled-task-validation"
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["check-ref-format", "--branch", candidateBranch],
            in: projectPath
        )
        try requireProjectIdentity(expectedProjectIdentity, at: projectPath)
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
    }

    func validateWorktreeTargetIsAvailable(_ worktreePath: String) throws {
        try rejectWorktreeDestinationSymlink(at: worktreePath)
        guard !FileManager.default.fileExists(atPath: worktreePath) else {
            throw GitError.commandFailed("The worktree destination is no longer available: \(worktreePath)")
        }
    }

    func captureWorktreeTargetParentIdentity(
        targetPath: String,
        expectedProjectIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws -> TaskWorkspaceFileSystemIdentity? {
        guard expectedProjectIdentity != nil else {
            return nil
        }
        let parentPath = URL(fileURLWithPath: targetPath, isDirectory: true)
            .deletingLastPathComponent()
            .path
        guard CanonicalPath.normalize(parentPath) == parentPath,
              let identity = currentDirectoryIdentity(at: parentPath) else {
            throw worktreeDestinationChangedError(targetPath)
        }
        return identity
    }

    func validateWorktreeTargetParent(
        targetPath: String,
        projectPath: String,
        worktreesBase: String,
        expectedParentIdentity: TaskWorkspaceFileSystemIdentity?
    ) throws {
        try validateWorktreeDestination(projectPath: projectPath, worktreesBase: worktreesBase)
        let parentPath = URL(fileURLWithPath: targetPath, isDirectory: true)
            .deletingLastPathComponent()
            .path
        guard let expectedParentIdentity,
              CanonicalPath.normalize(parentPath) == parentPath,
              currentDirectoryIdentity(at: parentPath) == expectedParentIdentity else {
            throw worktreeDestinationChangedError(targetPath)
        }
    }

    private func worktreeDestinationChangedError(_ targetPath: String) -> GitError {
        GitError.commandFailed("The worktree destination changed before creation: \(targetPath)")
    }

    private func rejectWorktreeDestinationSymlink(at path: String) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil else {
            throw GitError.commandFailed(
                "The configured worktrees path is not a directory: \(path)"
            )
        }
    }

    private func rejectNoncanonicalWorktreeDestination(
        at path: String,
        reporting configuredPath: String
    ) throws {
        guard CanonicalPath.normalize(path) == path else {
            throw GitError.commandFailed(
                "The configured worktrees path is not a directory: \(configuredPath)"
            )
        }
    }
}

struct WorktreeRemovalIdentityValidation {
    static let unchecked = WorktreeRemovalIdentityValidation(
        project: nil,
        worktree: nil,
        validatesWorktree: false
    )

    let project: TaskWorkspaceFileSystemIdentity?
    let worktree: TaskWorkspaceFileSystemIdentity?
    let validatesWorktree: Bool
}

extension DefaultWorktreeManager {
    func captureCreatedBranchOID(
        _ prepared: PreparedWorktreeCreation,
        worktreeIdentity: TaskWorkspaceFileSystemIdentity?
    ) async throws -> String {
        let identityValidation = WorktreeCreationIdentityValidation(
            project: prepared.expectedProjectIdentity,
            worktree: worktreeIdentity
        )
        try requireCreationIdentities(
            identityValidation,
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: prepared.projectPath
        )
        try requireCreationIdentities(
            identityValidation,
            projectPath: prepared.projectPath,
            worktreePath: prepared.target.path
        )
        guard result.succeeded else {
            throw Self.makeGitError(from: result)
        }
        let canonicalWorktreePath = CanonicalPath.normalize(prepared.target.path)
        guard let headOID = parseWorktreeList(result.stdout).first(where: {
            CanonicalPath.normalize($0.path) == canonicalWorktreePath &&
                $0.branch == prepared.target.branch
        })?.headOID else {
            throw GitError.commandFailed(
                "Unable to prove the created branch ref for \(prepared.target.branch)"
            )
        }
        return headOID
    }

    func requireProjectIdentity(
        _ expectedIdentity: TaskWorkspaceFileSystemIdentity?,
        at projectPath: String
    ) throws {
        guard let expectedIdentity else {
            return
        }
        guard CanonicalPath.normalize(projectPath) == projectPath,
              currentDirectoryIdentity(at: projectPath) == expectedIdentity else {
            throw WorktreeSourceValidationError.sourceProjectChanged(projectPath)
        }
    }

    func requireWorktreeIdentity(
        _ validation: WorktreeRemovalIdentityValidation,
        at worktreePath: String
    ) throws {
        guard validation.validatesWorktree else {
            return
        }
        let currentIdentity = currentDirectoryIdentity(at: worktreePath)
        guard currentIdentity == nil || (
            CanonicalPath.normalize(worktreePath) == worktreePath &&
                currentIdentity == validation.worktree
        ) else {
            throw WorktreeSourceValidationError.ownedWorktreeChanged(worktreePath)
        }
    }

    func currentDirectoryIdentity(at path: String) -> TaskWorkspaceFileSystemIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return TaskWorkspaceFileSystemIdentity(
            systemNumber: systemNumber.uint64Value,
            fileNumber: fileNumber.uint64Value
        )
    }
}
