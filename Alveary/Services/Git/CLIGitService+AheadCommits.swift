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

    func aheadCompareRef(baseBranch: String, remoteName: String?, in directory: String) async throws -> String {
        // Keep ahead counts and ahead commit lists aligned, including older projects that
        // predate persisted remote metadata but still have a usable branch upstream.
        if let remoteName,
           await remoteTrackingRefExists(remoteName: remoteName, baseBranch: baseBranch, in: directory) {
            return "\(remoteName)/\(baseBranch)"
        }

        if remoteName == nil,
           let upstream = await currentBranchUpstream(in: directory) {
            return upstream
        }

        if remoteName == nil,
           await remoteTrackingRefExists(remoteName: "origin", baseBranch: baseBranch, in: directory) {
            return "origin/\(baseBranch)"
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
