import XCTest

@testable import Alveary

final class FileListManagerTests: XCTestCase {
    func testFilesCachesResultsUntilInvalidated() async {
        let gitService = MockGitService(listFilesResults: [["Sources/App.swift"], ["Sources/New.swift"]])
        let manager = GitFileListManager(gitService: gitService)

        let first = await manager.files(for: "/tmp/project")
        let second = await manager.files(for: "/tmp/project")
        await manager.invalidateCache(for: "/tmp/project")
        let third = await manager.files(for: "/tmp/project")
        let callCount = await gitService.listFilesCallCount()

        XCTAssertEqual(first, ["Sources/App.swift"])
        XCTAssertEqual(second, ["Sources/App.swift"])
        XCTAssertEqual(third, ["Sources/New.swift"])
        XCTAssertEqual(callCount, 2)
    }

    func testFilesReturnsEmptyArrayWhenGitLookupFails() async {
        let gitService = MockGitService(listFilesError: GitError.notARepository)
        let manager = GitFileListManager(gitService: gitService)

        let files = await manager.files(for: "/tmp/project")

        XCTAssertTrue(files.isEmpty)
    }

    func testWarmCacheFailureDoesNotPoisonLaterSuccessfulLookup() async {
        let gitService = MockGitService(
            listFilesResults: [["Sources/App.swift"]],
            listFilesErrors: [GitError.notARepository, nil]
        )
        let manager = GitFileListManager(gitService: gitService)

        await manager.warmCache(for: "/tmp/project")
        let files = await manager.files(for: "/tmp/project")

        XCTAssertEqual(files, ["Sources/App.swift"])
    }
}

private actor MockGitService: GitService {
    private let listFilesError: Error?
    private var listFilesErrors: [Error?]
    private var listFilesResults: [[String]]
    private var callCount = 0

    init(listFilesResults: [[String]] = [], listFilesError: Error? = nil, listFilesErrors: [Error?] = []) {
        self.listFilesResults = listFilesResults
        self.listFilesError = listFilesError
        self.listFilesErrors = listFilesErrors
    }

    func status(in directory: String) async throws -> [FileStatus] { [] }
    func diffStats(in directory: String, knownStatuses: [FileStatus]?) async throws -> DiffStats { .empty }
    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String { "" }
    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String { "" }
    func stage(paths: [String], in directory: String) async throws {}
    func unstage(paths: [String], in directory: String) async throws {}
    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {}
    func log(in directory: String, limit: Int) async throws -> [CommitInfo] { [] }
    func currentBranch(in directory: String) async throws -> String { "main" }

    func listFiles(in directory: String) async throws -> [String] {
        callCount += 1
        if !listFilesErrors.isEmpty {
            if let error = listFilesErrors.removeFirst() {
                throw error
            }
        } else if let listFilesError {
            throw listFilesError
        }
        if !listFilesResults.isEmpty {
            return listFilesResults.removeFirst()
        }
        return []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int { 0 }

    func listFilesCallCount() -> Int {
        callCount
    }
}
