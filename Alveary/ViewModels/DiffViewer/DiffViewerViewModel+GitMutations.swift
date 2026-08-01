import Foundation

// Stage, unstage, and discard mutations from the Diff Viewer file list. Each
// mutation refreshes the workspace with `.localGitMutation` so the visible
// status and stats track the change immediately.
extension DiffViewerViewModel {
    func clearGitError() { diffStore.clearGitError() }

    func presentGitError(_ message: String) { diffStore.presentGitError(message) }

    func stage(files: [FileStatus], in directory: String) async throws {
        try await stage(paths: DiffViewerPathSupport.uniquePaths(files.map(\.path)), in: directory)
    }

    func stage(paths: [String], in directory: String) async throws {
        try await gitService.stage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func unstage(files: [FileStatus], in directory: String) async throws {
        try await unstage(paths: DiffViewerPathSupport.uniquePaths(files.map(\.path)), in: directory)
    }

    func unstage(paths: [String], in directory: String) async throws {
        try await gitService.unstage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(files: [FileStatus], in directory: String) async throws {
        let stagedFiles = files.filter(\.isStaged)
        let stagedPaths = DiffViewerPathSupport.discardPaths(for: stagedFiles)
        let stagedPathSet = Set(stagedPaths)

        let unstagedPaths = DiffViewerPathSupport.discardPaths(for: files.filter { !$0.isStaged })
            .filter { !stagedPathSet.contains($0) }

        if !stagedPaths.isEmpty {
            try await gitService.discard(paths: stagedPaths, scope: .all, in: directory)
        }

        if !unstagedPaths.isEmpty {
            try await gitService.discard(paths: unstagedPaths, scope: .worktreeOnly, in: directory)
        }

        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(paths: [String], in directory: String) async throws {
        try await gitService.discard(paths: paths, scope: .all, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    /// Rides `performRefresh`: two extra probes per refresh rather than a
    /// second polling pass. A failed probe reads as nothing to push and no
    /// branch — both are informational — and nil means the snapshot went stale
    /// across the probes, so the caller must publish nothing. The probes share
    /// one `isCurrent` guard so the flags and the branch publish atomically.
    func resolvedWorkingState(
        for snapshot: DiffWorkspaceRefreshSnapshot,
        in directory: String
    ) async -> DiffViewerWorkingState? {
        let hasUnpushedCommits = (try? await gitService.hasUnpushedCommits(
            baseBranch: snapshot.target.baseRef,
            remoteName: snapshot.target.remoteName,
            in: directory
        )) ?? false
        let currentBranch = try? await gitService.currentBranch(in: directory)
        guard diffStore.isCurrent(snapshot) else {
            return nil
        }
        return DiffViewerWorkingState(
            hasChanges: !snapshot.files.isEmpty,
            hasUnpushedCommits: hasUnpushedCommits,
            currentBranch: Self.displayableBranchName(currentBranch)
        )
    }

    /// `git rev-parse --abbrev-ref HEAD` prints the literal `HEAD` on a detached
    /// checkout, which is a worse label than none at all.
    static func displayableBranchName(_ branch: String?) -> String? {
        guard let trimmed = branch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "HEAD" else {
            return nil
        }

        return trimmed
    }

    /// Pushes the checked-out branch; the follow-up refresh recomputes
    /// `workingState.hasUnpushedCommits`, which is what walks the footer's
    /// button on to its next action. `GitError.nonFastForwardPushRequired`
    /// propagates so the pane can offer a force push.
    func push(force: Bool, in directory: String) async throws {
        let remoteName = diffStore.activeTarget?.remoteName
        if force {
            try await gitService.forcePushCurrentBranch(remoteName: remoteName, in: directory)
        } else {
            try await gitService.pushCurrentBranch(remoteName: remoteName, in: directory)
        }
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }
}
