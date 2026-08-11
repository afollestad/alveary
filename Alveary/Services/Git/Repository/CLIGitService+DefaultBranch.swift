import Foundation

/// A resolved default branch plus whether its remote-tracking ref is already
/// known to exist, so `aheadCompareRef` can build `<remote>/<branch>` without
/// re-running the probe that proved it.
struct GitDefaultBranch: Equatable {
    let name: String
    let hasRemoteTrackingRef: Bool
}

// Resolves the repository's default branch — what "not yet on the default
// branch" means for the commit list, the ahead counts, and the pull-request
// base. See the Default Branch section in this folder's AGENTS.md.
extension CLIGitService {
    /// Conventional default-branch names, most likely first. Probed only when
    /// the repository does not record its own default.
    static let conventionalDefaultBranches = ["main", "master"]

    /// The repository's default branch, or nil when none can be discovered.
    ///
    /// Callers must treat a persisted base branch as a fallback hint rather than
    /// the authority: `Project.baseRef` is captured once at project import and
    /// falls back to whichever branch happened to be checked out then, so a
    /// project imported on a feature branch pins the wrong base forever.
    func defaultBranch(remoteName: String?, in directory: String) async -> String? {
        let remote = await effectiveRemoteName(remoteName, in: directory)
        return await resolvedDefaultBranch(remote: remote, in: directory)?.name
    }

    /// Takes an already-resolved remote so a caller that needed it anyway does
    /// not pay for a second `git remote`.
    func resolvedDefaultBranch(remote: String?, in directory: String) async -> GitDefaultBranch? {
        // `refs/remotes/<remote>/HEAD` is a symbolic ref *to* the default
        // branch's remote-tracking ref, so resolving it also proves that ref
        // exists.
        if let remote, let recorded = await remoteHeadBranch(remoteName: remote, in: directory) {
            return GitDefaultBranch(name: recorded, hasRemoteTrackingRef: true)
        }

        // Only `git clone` writes that symbolic ref, and plenty of working
        // clones lack it, so fall back to the conventional names before giving
        // up and letting the caller use its stale hint.
        if let remote {
            for candidate in Self.conventionalDefaultBranches
            where await remoteTrackingRefExists(remoteName: remote, baseBranch: candidate, in: directory) {
                return GitDefaultBranch(name: candidate, hasRemoteTrackingRef: true)
            }
        }

        for candidate in Self.conventionalDefaultBranches
        where await localBranchExists(candidate, in: directory) {
            return GitDefaultBranch(name: candidate, hasRemoteTrackingRef: false)
        }

        return nil
    }

    /// The remote to resolve against: the caller's when it has one, otherwise
    /// the repository's own. Older projects predate persisted remote metadata,
    /// and a Task thread without a project never had any — and reading the
    /// remote from the repository is what keeps those from silently falling
    /// back to the branch upstream, which answers a different question.
    func effectiveRemoteName(_ remoteName: String?, in directory: String) async -> String? {
        if let remoteName {
            return remoteName
        }

        let result = try? await shell.run(executable: "/usr/bin/git", args: ["remote"], in: directory)
        guard result?.succeeded == true else {
            return nil
        }

        let remotes = (result?.stdout ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if remotes.count == 1 {
            return remotes[0]
        }
        return remotes.contains("origin") ? "origin" : nil
    }

    func localBranchExists(_ branch: String, in directory: String) async -> Bool {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            in: directory
        )
        return result?.succeeded == true
    }

    private func remoteHeadBranch(remoteName: String, in directory: String) async -> String? {
        let result = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["symbolic-ref", "refs/remotes/\(remoteName)/HEAD"],
            in: directory
        )
        guard result?.succeeded == true else {
            return nil
        }

        let prefix = "refs/remotes/\(remoteName)/"
        let ref = (result?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ref.hasPrefix(prefix) else {
            return nil
        }

        let branch = String(ref.dropFirst(prefix.count))
        return branch.isEmpty ? nil : branch
    }
}
