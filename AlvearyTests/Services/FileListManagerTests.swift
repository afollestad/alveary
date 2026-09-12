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

    func testOrdinaryFolderEnumeratesNestedFilesWithoutGitStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("visible".utf8).write(to: root.appendingPathComponent("nested/note.txt"))
        try Data("index".utf8).write(to: root.appendingPathComponent(".git/index"))
        let manager = GitFileListManager(gitService: MockGitService(listFilesError: GitError.notARepository))
        let files = await manager.files(for: root.path)
        XCTAssertEqual(files, ["nested/note.txt"])
    }

    func testMutationInvalidatesOverlappingRootsButKeepsUnrelatedCaches() async {
        let git = MockGitService(listFilesResults: [["parent-old"], ["child-old"], ["unrelated"], ["parent-new"], ["child-new"]])
        let manager = GitFileListManager(gitService: git)
        _ = await manager.files(for: "/tmp/project")
        _ = await manager.files(for: "/tmp/project/child")
        _ = await manager.files(for: "/tmp/elsewhere")
        await manager.invalidateCache(for: "/tmp/project/child")
        let parent = await manager.files(for: "/tmp/project")
        let child = await manager.files(for: "/tmp/project/child")
        let unrelated = await manager.files(for: "/tmp/elsewhere")
        XCTAssertEqual(parent, ["parent-new"])
        XCTAssertEqual(child, ["child-new"])
        XCTAssertEqual(unrelated, ["unrelated"])
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
    func repositoryRoot(in directory: String) async throws -> String? { directory }

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
    func currentHeadHash(in directory: String) async throws -> String { "abc123" }

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
    func commitsAheadOfBaseDetails(baseBranch: String, remoteName: String?, in directory: String) async throws -> [CommitInfo] { [] }
    func diffForCommit(hash: String, in directory: String) async throws -> String { "" }
    func imageBlob(source: GitImageBlobSource, maxBytes: Int, in directory: String) async throws -> Data { Data() }

    func listFilesCallCount() -> Int {
        callCount
    }
}
