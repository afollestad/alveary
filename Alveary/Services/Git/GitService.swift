import Foundation

struct FileStatus: Identifiable, Sendable, Equatable {
    enum Status: String, Sendable {
        case modified
        case added
        case deleted
        case renamed
        case copied
        case untracked
        case unmerged
    }

    var id: String { path + (isStaged ? "-staged" : "") }

    let path: String
    let originalPath: String?
    let status: Status
    let isStaged: Bool
}

struct CommitInfo: Identifiable, Sendable, Equatable {
    var id: String { hash }

    let hash: String
    let message: String
    let author: String
    let date: Date
}

struct DiffStats: Sendable, Equatable {
    static let empty = DiffStats(additions: 0, deletions: 0)

    let additions: Int
    let deletions: Int

    var isEmpty: Bool {
        additions == 0 && deletions == 0
    }

    func adding(_ other: DiffStats) -> DiffStats {
        DiffStats(
            additions: additions + other.additions,
            deletions: deletions + other.deletions
        )
    }
}

enum DiffScope: Sendable, Equatable {
    case staged
    case unstaged
}

enum DiscardScope: Sendable, Equatable {
    case all
    case worktreeOnly
}

enum GitError: Error, Sendable, Equatable {
    case commandFailed(String)
    case notARepository
    case outputTooLarge(String)
}

extension GitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .notARepository:
            return "This project is not a Git repository"
        case .outputTooLarge(let message):
            return message
        }
    }
}

enum GitImageBlobSource: Sendable, Hashable {
    case worktree(path: String)
    case head(path: String)
    case index(path: String)
    case commit(hash: String, path: String)
    case commitParent(hash: String, path: String)
}

protocol GitService: Sendable {
    func status(in directory: String) async throws -> [FileStatus]
    // Pass freshly loaded status rows when available so callers do not run a
    // second porcelain status scan just to include untracked files in stats.
    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats
    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String
    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String
    func stage(paths: [String], in directory: String) async throws
    func unstage(paths: [String], in directory: String) async throws
    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws
    func log(in directory: String, limit: Int) async throws -> [CommitInfo]
    func currentBranch(in directory: String) async throws -> String
    func currentHeadHash(in directory: String) async throws -> String
    func listFiles(in directory: String) async throws -> [String]
    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int
    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo]
    func diffForCommit(hash: String, in directory: String) async throws -> String
    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data
}

extension GitService {
    func diffStats(in directory: String) async throws -> DiffStats {
        try await diffStats(in: directory, knownStatuses: nil)
    }

    func discard(paths: [String], in directory: String) async throws {
        try await discard(paths: paths, scope: .all, in: directory)
    }
}
