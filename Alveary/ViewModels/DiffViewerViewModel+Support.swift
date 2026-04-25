import Foundation

typealias DiffViewerDiffLoadResult = (raw: String, parsed: DiffFile?)

enum DiffViewerContextualAction: Equatable {
    case none
    case commit
    case openPR
    case viewPR(url: String)
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

struct DiffViewerRefreshRequest {
    let directory: String
    let reason: DiffViewerRefreshReason
    let invalidateFileListCache: Bool
    let invalidatePRCache: Bool

    func merged(with newer: DiffViewerRefreshRequest) -> DiffViewerRefreshRequest {
        guard directory == newer.directory else {
            return newer
        }

        return DiffViewerRefreshRequest(
            directory: directory,
            reason: reason.merged(with: newer.reason),
            invalidateFileListCache: invalidateFileListCache || newer.invalidateFileListCache,
            invalidatePRCache: invalidatePRCache || newer.invalidatePRCache
        )
    }
}

struct DiffViewerDiffStatsCacheKey: Hashable {
    let directory: String
    // Different compare bases can produce different counts for the same folder.
    let baseRef: String
    let remoteName: String?
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
                raw = try await gitService.syntheticAddedDiff(for: file.path, in: directory)
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

            try Task.checkCancellation()
            return (raw: raw, parsed: parsed)
        }
    }
}
