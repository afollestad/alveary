#if DEBUG
import Foundation

/// Answers the whole diff surface — toolbar `+N`/`-N`, the pane's file list, per-file diffs,
/// commits mode, branch label, and footer state — from canned data for demo paths, and forwards
/// everything else to the real service so a demo build still works against real projects.
///
/// `final class` holding only `let` state, matching `CLIGitService`: the toolbar reads stats on a
/// `Task.detached`, so the decorator has to be `Sendable` without `@unchecked`.
final class DemoGitService: GitService {
    private let wrapped: GitService

    init(wrapping wrapped: GitService) {
        self.wrapped = wrapped
    }

    // MARK: Canned reads

    func status(in directory: String) async throws -> [FileStatus] {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.status(in: directory)
        }
        return workspace.statuses
    }

    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.diffStats(in: directory, knownStatuses: knownStatuses)
        }
        return workspace.stats
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.diff(paths: paths, scope: scope, in: directory)
        }
        guard !paths.isEmpty else {
            return workspace.combinedDiff
        }
        return paths.compactMap { workspace.diffsByPath[$0] }.joined(separator: "\n")
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.syntheticAddedDiff(for: path, in: directory)
        }
        return workspace.diffsByPath[path] ?? ""
    }

    func currentBranch(in directory: String) async throws -> String {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.currentBranch(in: directory)
        }
        return workspace.branch
    }

    func currentHeadHash(in directory: String) async throws -> String {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.currentHeadHash(in: directory)
        }
        return workspace.commits.first?.hash ?? "0000000000000000000000000000000000000000"
    }

    func listFiles(in directory: String) async throws -> [String] {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.listFiles(in: directory)
        }
        return workspace.statuses.map(\.path).sorted()
    }

    /// The one protocol requirement that cannot throw, so a demo path with no canned workspace
    /// answers "undiscoverable" instead of `.notARepository`.
    func defaultBranch(remoteName: String?, in directory: String) async -> String? {
        if DemoGitWorkspaces.workspace(for: directory) != nil {
            return "main"
        }
        guard CanonicalPath.normalize(directory).hasPrefix(DemoGitWorkspaces.ownedPathPrefix) else {
            return await wrapped.defaultBranch(remoteName: remoteName, in: directory)
        }
        return nil
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.log(in: directory, limit: limit)
        }
        return Array(workspace.commits.prefix(limit))
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.commitsAheadOfBase(baseBranch: baseBranch, remoteName: remoteName, in: directory)
        }
        return workspace.commits.count
    }

    func commitsAheadOfBaseDetails(
        baseBranch: String,
        remoteName: String?,
        in directory: String
    ) async throws -> [CommitInfo] {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.commitsAheadOfBaseDetails(
                baseBranch: baseBranch,
                remoteName: remoteName,
                in: directory
            )
        }
        return workspace.commits
    }

    func hasUnpushedCommits(baseBranch: String, remoteName: String?, in directory: String) async throws -> Bool {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.hasUnpushedCommits(baseBranch: baseBranch, remoteName: remoteName, in: directory)
        }
        return workspace.hasUnpushedCommits
    }

    /// Production runs `git show --format=`, so a commit diff is bare unified diff text with no
    /// commit header.
    func diffForCommit(hash: String, in directory: String) async throws -> String {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.diffForCommit(hash: hash, in: directory)
        }
        guard let index = workspace.commits.firstIndex(where: { $0.hash == hash }) else {
            return workspace.combinedDiff
        }
        let ordered = workspace.statuses.compactMap { workspace.diffsByPath[$0.path] }
        return ordered.isEmpty ? workspace.combinedDiff : ordered[index % ordered.count]
    }

    func hasStagedChanges(in directory: String) async throws -> Bool {
        guard let workspace = try demoWorkspace(in: directory) else {
            return try await wrapped.hasStagedChanges(in: directory)
        }
        return workspace.statuses.contains(where: \.isStaged)
    }

    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data {
        guard try demoWorkspace(in: directory) != nil else {
            return try await wrapped.imageBlob(source: source, maxBytes: maxBytes, in: directory)
        }
        throw GitError.commandFailed("Image blobs are not available in demo mode")
    }

    // MARK: Mutations

    // Forwarded rather than faked: they fail visibly against a fake path, which is the honest
    // outcome for a DEBUG screenshot tool. The protocol's own defaults throw, so forwarding also
    // keeps a real project working in a demo build.

    func stage(paths: [String], in directory: String) async throws {
        try await wrapped.stage(paths: paths, in: directory)
    }

    func unstage(paths: [String], in directory: String) async throws {
        try await wrapped.unstage(paths: paths, in: directory)
    }

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {
        try await wrapped.discard(paths: paths, scope: scope, in: directory)
    }

    func validateBranchName(_ branchName: String, in directory: String) async throws -> Bool {
        try await wrapped.validateBranchName(branchName, in: directory)
    }

    func checkoutNewBranch(_ branchName: String, in directory: String) async throws {
        try await wrapped.checkoutNewBranch(branchName, in: directory)
    }

    func commit(message: String, includeUnstagedChanges: Bool, in directory: String) async throws {
        try await wrapped.commit(message: message, includeUnstagedChanges: includeUnstagedChanges, in: directory)
    }

    func pushCurrentBranch(remoteName: String?, in directory: String) async throws {
        try await wrapped.pushCurrentBranch(remoteName: remoteName, in: directory)
    }

    func forcePushCurrentBranch(remoteName: String?, in directory: String) async throws {
        try await wrapped.forcePushCurrentBranch(remoteName: remoteName, in: directory)
    }

    // MARK: Routing

    /// Returns the canned workspace for `directory`, `nil` when the real service should answer,
    /// and throws `.notARepository` for a demo path with no canned data — which is what renders
    /// the real "Git features unavailable" state for the non-git demo project.
    private func demoWorkspace(in directory: String) throws -> DemoGitWorkspace? {
        if let workspace = DemoGitWorkspaces.workspace(for: directory) {
            return workspace
        }
        guard CanonicalPath.normalize(directory).hasPrefix(DemoGitWorkspaces.ownedPathPrefix) else {
            return nil
        }
        throw GitError.notARepository
    }
}
#endif
