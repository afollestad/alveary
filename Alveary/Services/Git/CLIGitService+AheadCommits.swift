import Foundation

// Ahead-of-base and unpushed-commit queries. Count, details, and the unpushed
// check share `aheadCompareRef` so every surface agrees about which commits are
// ahead — see the Ahead Commits section in this folder's AGENTS.md.
extension CLIGitService {
    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        let compareRef = try await aheadCompareRef(baseBranch: baseBranch, remoteName: remoteName, in: directory)

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-list", "\(compareRef)..HEAD", "--count"],
            in: directory
        )
        guard result.succeeded else {
            return 0
        }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] {
        let compareRef = try await aheadCompareRef(baseBranch: baseBranch, remoteName: remoteName, in: directory)
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["log", "--pretty=format:%H%n%s%n%an%n%aI", "\(compareRef)..HEAD"],
            in: directory
        )
        guard result.succeeded else {
            throw Self.makeError(from: result)
        }
        return parseLog(result.stdout)
    }

    func hasUnpushedCommits(baseBranch: String, remoteName: String?, in directory: String) async throws -> Bool {
        // With an upstream, "unpushed" is exactly the commits the upstream lacks.
        if let upstream = await currentBranchUpstream(in: directory) {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["rev-list", "\(upstream)..HEAD", "--count"],
                in: directory
            )
            guard result.succeeded else {
                throw Self.makeError(from: result)
            }
            return (Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) > 0
        }

        // Never pushed: a first push is meaningful only when the branch has
        // commits the base does not — a checkout sitting exactly on base would
        // just mirror it.
        return try await commitsAheadOfBase(baseBranch: baseBranch, remoteName: remoteName, in: directory) > 0
    }

    /// Resolves what "ahead" is measured against, preferring the repository's
    /// actual default branch over the caller's persisted `baseBranch`.
    ///
    /// The persisted value is only a hint: `Project.baseRef` is captured once at
    /// import and falls back to whichever branch was checked out then, and a
    /// Task thread without a project carries no remote at all. Trusting it made
    /// this resolve to the current branch's upstream, which turned "commits not
    /// yet on the default branch" into "commits not yet pushed" — the same list
    /// the footer's push action already covers.
    ///
    /// On the default branch the remote-tracking form still yields the unpushed
    /// commits, which is the wanted answer there; off it, the list is everything
    /// the default branch does not have yet.
    func aheadCompareRef(baseBranch: String, remoteName: String?, in directory: String) async throws -> String {
        let remote = await effectiveRemoteName(remoteName, in: directory)

        if let resolved = await resolvedDefaultBranch(remote: remote, in: directory) {
            if let remote, resolved.hasRemoteTrackingRef {
                return "\(remote)/\(resolved.name)"
            }
            return resolved.name
        }

        // No discoverable default, so fall back to the caller's hint.
        if let remote, await remoteTrackingRefExists(remoteName: remote, baseBranch: baseBranch, in: directory) {
            return "\(remote)/\(baseBranch)"
        }

        if await localBranchExists(baseBranch, in: directory) {
            return baseBranch
        }

        // Nothing base-like exists at all. The upstream answers a different
        // question — commits not yet pushed — but it is the last ref that can
        // produce a meaningful list here.
        if let upstream = await currentBranchUpstream(in: directory) {
            return upstream
        }

        return baseBranch
    }

    func remoteTrackingRefExists(remoteName: String, baseBranch: String, in directory: String) async -> Bool {
        let remoteRef = "refs/remotes/\(remoteName)/\(baseBranch)"
        let remoteExists = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["show-ref", "--verify", "--quiet", remoteRef],
            in: directory
        )
        return remoteExists?.succeeded == true
    }

    func currentBranchUpstream(in directory: String) async -> String? {
        let upstream = try? await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
            in: directory
        )
        guard upstream?.succeeded == true else {
            return nil
        }

        let ref = upstream?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ref.isEmpty ? nil : ref
    }
}
