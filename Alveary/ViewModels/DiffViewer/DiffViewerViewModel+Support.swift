import Foundation

struct DiffViewerDiffLoadResult {
    let raw: String
    let parsed: DiffFile?
    let imagePreview: DiffImagePreview?
}

struct DiffViewerCommitDiffLoadResult {
    let raw: String
    let parsed: [DiffFile]
    let imagePreviews: [String: DiffImagePreview]
}

enum DiffWorkspaceLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum DiffViewerContextualAction: Equatable {
    case none
    case commit
    case openPR
    case viewPR(url: String)
}

// File rows can appear twice for the same path when staged and unstaged changes coexist.
// Include staged state so batch selection addresses the row the user actually selected.
struct DiffViewerFileSelectionKey: Hashable {
    let path: String
    let isStaged: Bool

    init(_ file: FileStatus) {
        self.path = file.path
        self.isStaged = file.isStaged
    }
}

enum DiffViewerFileSelectionBehavior {
    case single
    case toggle
    case range
    case rangeUnion
}

enum DiffViewerCommitSelectionBehavior {
    case single
    case toggle
    case range
    case rangeUnion
}

struct DiffViewerPreparedFileSelection {
    let file: FileStatus
    let target: DiffWorkspaceTarget
    let generation: UInt64
    let directory: String
}

struct DiffViewerPreparedCommitSelection {
    let commit: CommitInfo
    let target: DiffWorkspaceTarget
}

enum DiffViewerRefreshReason: Equatable {
    case fsEvent(changedPaths: Set<String>)
    case agentTurnCompleted
    case appBecameActive
    case localGitMutation
    case manual
    case idlePoll
    case threadSwitch

    fileprivate func merged(with newer: DiffViewerRefreshReason) -> DiffViewerRefreshReason {
        switch (self, newer) {
        case let (.fsEvent(existingPaths), .fsEvent(newPaths)):
            return .fsEvent(changedPaths: existingPaths.union(newPaths))
        default:
            return priority >= newer.priority ? self : newer
        }
    }

    private var priority: Int {
        switch self {
        case .manual:
            return 6
        case .localGitMutation:
            return 5
        case .appBecameActive:
            return 4
        case .threadSwitch:
            return 3
        case .agentTurnCompleted:
            return 2
        case .fsEvent:
            return 1
        case .idlePoll:
            return 0
        }
    }
}

// How much of the diff workspace a target switch or refresh should load.
// `.toolbarStatsOnly` keeps the toolbar diff summary fresh while the pane is
// hidden, skipping contextual-action (PR lookup) and selected-diff work until
// the pane is revealed.
enum DiffViewerSwitchScope {
    case full
    case toolbarStatsOnly
}

struct DiffViewerRefreshRequest {
    let directory: String
    let reason: DiffViewerRefreshReason
    let invalidateFileListCache: Bool
    let invalidatePRCache: Bool
    let scope: DiffViewerSwitchScope

    func merged(with newer: DiffViewerRefreshRequest) -> DiffViewerRefreshRequest {
        guard directory == newer.directory else {
            return newer
        }

        return DiffViewerRefreshRequest(
            directory: directory,
            reason: reason.merged(with: newer.reason),
            invalidateFileListCache: invalidateFileListCache || newer.invalidateFileListCache,
            invalidatePRCache: invalidatePRCache || newer.invalidatePRCache,
            scope: scope == .full || newer.scope == .full ? .full : .toolbarStatsOnly
        )
    }
}

struct DiffWorkspaceTarget: Equatable, Hashable {
    let projectPath: String
    let worktreePath: String?
    let directory: String
    let baseRef: String
    let remoteName: String?

    var statsCacheKey: DiffWorkspaceStatsCacheKey {
        DiffWorkspaceStatsCacheKey(
            projectPath: projectPath,
            worktreePath: worktreePath,
            baseRef: baseRef,
            remoteName: remoteName
        )
    }
}

struct DiffWorkspaceStatsCacheKey: Hashable {
    // Project and worktree paths deliberately both participate in the key: the
    // base checkout and each active worktree can have different local changes.
    let projectPath: String
    let worktreePath: String?
    // Different compare bases can produce different counts for the same folder.
    let baseRef: String
    let remoteName: String?
}

struct DiffWorkspaceRefreshSnapshot: Equatable {
    let target: DiffWorkspaceTarget
    let generation: UInt64
    let files: [FileStatus]
    let error: String?
    let isGitRepository: Bool
}

enum DiffViewerPathSupport {
    static func diffPaths(for file: FileStatus) -> [String] {
        if file.status == .renamed, let originalPath = file.originalPath {
            return [originalPath, file.path]
        }

        return [file.path]
    }

    static func discardPaths(for files: [FileStatus]) -> [String] {
        var paths: [String] = []

        for file in files {
            if file.status == .renamed, let originalPath = file.originalPath {
                paths.append(originalPath)
                paths.append(file.path)
            } else {
                paths.append(file.path)
            }
        }

        return uniquePaths(paths)
    }

    static func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }
}

enum DiffViewerDiffTaskFactory {
    static func makeTask(
        for file: FileStatus,
        in directory: String,
        gitService: GitService
    ) -> Task<DiffViewerDiffLoadResult, Error> {
        Task(priority: .userInitiated) {
            let raw: String
            if file.status == .untracked {
                do {
                    raw = try await gitService.syntheticAddedDiff(for: file.path, in: directory)
                } catch GitError.outputTooLarge(_) where DiffImagePreviewSupport.canPreviewImage(path: file.path) {
                    // Large raster images should skip text diff synthesis and let the
                    // background ImageIO preview loader enforce image-specific bounds.
                    raw = DiffImagePreviewSupport.syntheticAddedBinaryDiff(for: file.path)
                }
            } else {
                raw = try await gitService.diff(
                    paths: DiffViewerPathSupport.diffPaths(for: file),
                    scope: file.isStaged ? .staged : .unstaged,
                    in: directory
                )
            }

            try Task.checkCancellation()

            guard raw.utf8.count <= 5 * 1024 * 1024 else {
                throw GitError.outputTooLarge("Diff preview exceeded 5MB")
            }

            let parsed = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return DiffParser.parse(raw).first
            }.value

            let imagePreview: DiffImagePreview?
            if let parsed,
               DiffImagePreviewSupport.canPreviewCurrentImage(for: parsed, fileStatus: file) {
                let headHash = (try? await gitService.currentHeadHash(in: directory)) ?? "no-head"
                imagePreview = DiffImagePreviewSupport.preview(for: parsed, fileStatus: file, headHash: headHash)
            } else {
                imagePreview = nil
            }

            try Task.checkCancellation()
            return DiffViewerDiffLoadResult(raw: raw, parsed: parsed, imagePreview: imagePreview)
        }
    }
}

enum DiffViewerCommitDiffTaskFactory {
    static func makeTask(
        for commit: CommitInfo,
        in directory: String,
        gitService: GitService
    ) -> Task<DiffViewerCommitDiffLoadResult, Error> {
        Task(priority: .userInitiated) {
            let raw = try await gitService.diffForCommit(hash: commit.hash, in: directory)
            try Task.checkCancellation()

            let parsed = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return DiffParser.parse(raw)
            }.value

            let imagePreviews = Dictionary(
                uniqueKeysWithValues: parsed.enumerated().compactMap { fileIndex, file in
                    DiffImagePreviewSupport.preview(for: file, commitHash: commit.hash).map {
                        (DiffImagePreviewSupport.fileID(for: file, fileIndex: fileIndex), $0)
                    }
                }
            )

            try Task.checkCancellation()
            return DiffViewerCommitDiffLoadResult(raw: raw, parsed: parsed, imagePreviews: imagePreviews)
        }
    }
}

@MainActor
extension DiffViewerViewModel {
    func selectAllFilesImmediately(in directory: String) -> DiffViewerPreparedFileSelection? {
        diffStore.selectAllFiles(in: directory)
    }

    func selectAllFiles(in directory: String) async {
        guard let preparedSelection = selectAllFilesImmediately(in: directory) else {
            return
        }

        await loadSelectedFileDiff(preparedSelection)
    }

    @discardableResult
    func selectAdjacentFile(forward: Bool) async -> Bool {
        guard let activeDirectory else {
            return false
        }

        return await diffStore.selectAdjacentFile(forward: forward, in: activeDirectory)
    }

    func adjacentFile(forward: Bool) -> FileStatus? {
        guard let activeDirectory else {
            return nil
        }

        return diffStore.adjacentFile(forward: forward, in: activeDirectory)
    }

    @discardableResult
    func selectAdjacentCommit(forward: Bool) async -> Bool {
        guard diffStore.activeTarget != nil else {
            clearCommitState()
            return false
        }

        let currentIndex = selectedCommit.flatMap { selectedCommit in
            aheadCommits.firstIndex { $0.id == selectedCommit.id }
        }
        guard let nextIndex = diffViewerAdjacentIndex(in: aheadCommits.indices, from: currentIndex, forward: forward) else {
            return false
        }

        await selectCommit(aheadCommits[nextIndex], behavior: .single)
        return true
    }

    func adjacentCommit(from commitID: String?, forward: Bool) -> CommitInfo? {
        let currentIndex = commitID.flatMap { commitID in
            aheadCommits.firstIndex { $0.id == commitID }
        }
        guard let nextIndex = diffViewerAdjacentIndex(in: aheadCommits.indices, from: currentIndex, forward: forward) else {
            return nil
        }

        return aheadCommits[nextIndex]
    }
}
