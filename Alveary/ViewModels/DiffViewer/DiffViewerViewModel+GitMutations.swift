import Foundation

// Stage, unstage, and discard mutations from the Diff Viewer file list. Each
// mutation refreshes the workspace with `.localGitMutation` so the visible
// status and stats track the change immediately.
extension DiffViewerViewModel {
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
}
