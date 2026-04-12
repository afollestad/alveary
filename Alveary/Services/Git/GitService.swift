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
            return "The selected directory is not a Git repository"
        case .outputTooLarge(let message):
            return message
        }
    }
}

protocol GitService: Sendable {
    func status(in directory: String) async throws -> [FileStatus]
    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String
    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String
    func stage(paths: [String], in directory: String) async throws
    func unstage(paths: [String], in directory: String) async throws
    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws
    func log(in directory: String, limit: Int) async throws -> [CommitInfo]
    func currentBranch(in directory: String) async throws -> String
    func listFiles(in directory: String) async throws -> [String]
    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int
}

extension GitService {
    func discard(paths: [String], in directory: String) async throws {
        try await discard(paths: paths, scope: .all, in: directory)
    }
}
