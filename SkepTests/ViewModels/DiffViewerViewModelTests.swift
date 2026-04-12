import Foundation
import XCTest

@testable import Skep

@MainActor
final class DiffViewerViewModelTests: XCTestCase {
    func testBackgroundWatchCallbackDispatchesRefreshToMainActor() async {
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: Array(repeating: .success([]), count: 6)
            ),
            fsEventDebounceDuration: .milliseconds(20),
            idlePollInterval: .seconds(10)
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let initialStatusCalls = await fixture.gitService.statusCallCount()
        let ownerAddress = Int(bitPattern: Unmanaged.passUnretained(fixture.viewModel).toOpaque())

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let ownerPointer = UnsafeMutableRawPointer(bitPattern: ownerAddress)!
                let owner = Unmanaged<DiffViewerViewModel>.fromOpaque(ownerPointer).takeUnretainedValue()
                DiffViewerViewModel.dispatchWatchEvent(changedPaths: ["Sources/Foo.swift"], owner: owner)
                continuation.resume()
            }
        }

        try? await Task.sleep(for: .milliseconds(60))
        let finalStatusCalls = await fixture.gitService.statusCallCount()

        XCTAssertEqual(finalStatusCalls, initialStatusCalls + 1)
    }

    func testWatchingLifecycleStartsIdlePollingAndStopsWhenDisabled() async throws {
        let fixture = TestFixture(
            gitService: MockGitService(statusResults: Array(repeating: .success([]), count: 8)),
            idlePollInterval: .milliseconds(20)
        )
        defer { fixture.viewModel.tearDown() }

        try FileManager.default.createDirectory(atPath: fixture.directory, withIntermediateDirectories: true)

        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let initialStatusCalls = await fixture.gitService.statusCallCount()
        try? await Task.sleep(for: .milliseconds(70))
        let polledStatusCalls = await fixture.gitService.statusCallCount()

        XCTAssertGreaterThan(polledStatusCalls, initialStatusCalls)

        fixture.viewModel.setWatchingEnabled(false)
        let callsAfterDisable = await fixture.gitService.statusCallCount()

        try? await Task.sleep(for: .milliseconds(70))
        let finalStatusCalls = await fixture.gitService.statusCallCount()

        XCTAssertEqual(finalStatusCalls, callsAfterDisable)
    }

    func testFsEventDebounceCoalescesRapidRefreshes() async {
        let fixture = TestFixture(
            gitService: MockGitService(statusResults: Array(repeating: .success([]), count: 6)),
            fsEventDebounceDuration: .milliseconds(40),
            idlePollInterval: .seconds(10)
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let initialStatusCalls = await fixture.gitService.statusCallCount()

        fixture.viewModel.handleFSEventsForTesting(changedPaths: ["Sources/Foo.swift"])
        try? await Task.sleep(for: .milliseconds(10))
        fixture.viewModel.handleFSEventsForTesting(changedPaths: ["Sources/Bar.swift"])
        try? await Task.sleep(for: .milliseconds(80))
        let finalStatusCalls = await fixture.gitService.statusCallCount()

        XCTAssertEqual(finalStatusCalls, initialStatusCalls + 1)
    }

    func testAppWillTerminateStopsWatchingBeforeIdlePollRunsAgain() async throws {
        let fixture = TestFixture(
            gitService: MockGitService(statusResults: Array(repeating: .success([]), count: 6)),
            idlePollInterval: .milliseconds(200)
        )
        defer { fixture.viewModel.tearDown() }

        try FileManager.default.createDirectory(atPath: fixture.directory, withIntermediateDirectories: true)

        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let initialStatusCalls = await fixture.gitService.statusCallCount()
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)
        try? await Task.sleep(for: .milliseconds(260))
        let finalStatusCalls = await fixture.gitService.statusCallCount()

        XCTAssertEqual(finalStatusCalls, initialStatusCalls)
    }

    func testSelectFileUsesSyntheticDiffForUntrackedFiles() async {
        let untrackedFile = FileStatus(path: "notes.txt", originalPath: nil, status: .untracked, isStaged: false)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([untrackedFile])],
                syntheticDiffResults: [Self.addedDiff(path: "notes.txt", content: "hello")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.viewModel.selectFile(untrackedFile, in: fixture.directory)
        let syntheticDiffCalls = await fixture.gitService.syntheticDiffCalls()
        let diffCalls = await fixture.gitService.diffCalls()

        XCTAssertEqual(fixture.viewModel.contextualAction, .commit)
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, "notes.txt")
        XCTAssertEqual(syntheticDiffCalls, ["notes.txt"])
        XCTAssertTrue(diffCalls.isEmpty)
    }

    func testSelectFileDiffsBothPathsForRename() async {
        let renamedFile = FileStatus(path: "new.swift", originalPath: "old.swift", status: .renamed, isStaged: true)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([renamedFile])],
                diffResults: [Self.renameDiff(from: "old.swift", to: "new.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(renamedFile, in: fixture.directory)

        let diffCalls = await fixture.gitService.diffCalls()
        XCTAssertEqual(diffCalls, [.init(paths: ["old.swift", "new.swift"], scope: .staged, directory: fixture.directory)])
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, "new.swift")
        XCTAssertTrue(fixture.viewModel.parsedDiff?.isRenamed == true)
    }

    func testRefreshReconcilesSelectionAcrossRenamePathChanges() async {
        let initialSelection = FileStatus(path: "new.swift", originalPath: "old.swift", status: .renamed, isStaged: true)
        let updatedSelection = FileStatus(path: "newer.swift", originalPath: "old.swift", status: .renamed, isStaged: true)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([initialSelection]), .success([updatedSelection])],
                diffResults: [
                    Self.renameDiff(from: "old.swift", to: "new.swift"),
                    Self.renameDiff(from: "old.swift", to: "newer.swift")
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.selectFile(initialSelection, in: fixture.directory)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)

        XCTAssertEqual(fixture.viewModel.selectedFile?.path, "newer.swift")
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, "newer.swift")

        let diffCalls = await fixture.gitService.diffCalls()
        XCTAssertEqual(diffCalls.count, 2)
        XCTAssertEqual(diffCalls.last, .init(paths: ["old.swift", "newer.swift"], scope: .staged, directory: fixture.directory))
    }

    func testFsEventRefreshSkipsSelectedDiffReloadForUnrelatedPaths() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([modifiedFile]), .success([modifiedFile])],
                diffResults: [Self.modifiedDiff(path: "feature.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.viewModel.selectFile(modifiedFile, in: fixture.directory)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .fsEvent(changedPaths: ["other.swift"]))
        let diffCallCount = await fixture.gitService.diffCalls().count

        XCTAssertEqual(diffCallCount, 1)
        XCTAssertEqual(fixture.viewModel.selectedFile?.path, "feature.swift")
    }

    func testRefreshFailureClearsContextualActionAndSkipsSelectedDiffReload() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([modifiedFile]), .failure(GitError.notARepository)],
                diffResults: [Self.modifiedDiff(path: "feature.swift")]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.viewModel.selectFile(modifiedFile, in: fixture.directory)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)
        let diffCallCount = await fixture.gitService.diffCalls().count
        let listPRCallCount = fixture.gitHubService.listPRCallCount()

        XCTAssertEqual(fixture.viewModel.gitError, "Git status failed: The selected directory is not a Git repository")
        XCTAssertEqual(fixture.viewModel.contextualAction, .none)
        XCTAssertEqual(diffCallCount, 1)
        XCTAssertEqual(listPRCallCount, 0)
    }

    func testSelectFileCancelsSupersededDiffLoad() async {
        let slowFile = FileStatus(path: "slow.swift", originalPath: nil, status: .modified, isStaged: false)
        let fastFile = FileStatus(path: "fast.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([slowFile, fastFile])],
                diffResults: [Self.modifiedDiff(path: "slow.swift"), Self.modifiedDiff(path: "fast.swift")],
                diffDelays: [.milliseconds(250), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let slowSelectionTask = Task {
            await fixture.viewModel.selectFile(slowFile, in: fixture.directory)
        }
        try? await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(fixture.viewModel.selectedFile?.path, "slow.swift")
        XCTAssertTrue(fixture.viewModel.isLoadingSelectedDiff)

        await fixture.viewModel.selectFile(fastFile, in: fixture.directory)
        await slowSelectionTask.value

        XCTAssertEqual(fixture.viewModel.selectedFile?.path, "fast.swift")
        XCTAssertEqual(fixture.viewModel.parsedDiff?.path, "fast.swift")
        XCTAssertFalse(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertEqual(fixture.viewModel.gitError, nil)
    }

    func testDetermineActionReturnsExpectedToolbarStates() async {
        let commitFixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)])]
            )
        )
        defer { commitFixture.viewModel.tearDown() }

        await commitFixture.viewModel.switchToDirectory(
            commitFixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        XCTAssertEqual(commitFixture.viewModel.contextualAction, .commit)

        let viewPRFixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            ),
            gitHubService: MockGitHubService(
                listPRResults: [[
                    PRInfo(
                        number: 42,
                        title: "Feature",
                        url: "https://example.com/42",
                        state: "OPEN",
                        headRefName: "feature",
                        ciStatus: .pass
                    )
                ]]
            )
        )
        defer { viewPRFixture.viewModel.tearDown() }

        await viewPRFixture.viewModel.switchToDirectory(
            viewPRFixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        XCTAssertEqual(viewPRFixture.viewModel.contextualAction, .viewPR(url: "https://example.com/42"))

        let openPRFixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(2)
            )
        )
        defer { openPRFixture.viewModel.tearDown() }

        await openPRFixture.viewModel.switchToDirectory(
            openPRFixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        XCTAssertEqual(openPRFixture.viewModel.contextualAction, .openPR)
    }

    func testRefreshAndInvalidateFileListPreservesWarmPRCacheForLocalGitMutations() async {
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([]), .success([]), .success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            ),
            gitHubService: MockGitHubService(
                listPRResults: [[
                    PRInfo(
                        number: 42,
                        title: "Feature",
                        url: "https://example.com/42",
                        state: "OPEN",
                        headRefName: "feature",
                        ciStatus: .pass
                    )
                ]]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.refreshAndInvalidateFileList(in: fixture.directory, reason: .localGitMutation)
        await fixture.viewModel.refreshAndInvalidateFileList(in: fixture.directory, reason: .agentTurnCompleted)
        let listPRCallCount = fixture.gitHubService.listPRCallCount()
        let invalidatedDirectories = await fixture.fileListManager.invalidatedDirectories()

        XCTAssertEqual(listPRCallCount, 2)
        XCTAssertEqual(invalidatedDirectories, [fixture.directory, fixture.directory])
    }

    func testDiscardExpandsRenameToOriginalAndCurrentPath() async throws {
        let renamedFile = FileStatus(path: "new.swift", originalPath: "old.swift", status: .renamed, isStaged: true)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([renamedFile]), .success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        try await fixture.viewModel.discard(files: [renamedFile], in: fixture.directory)
        let discardCalls = await fixture.gitService.discardCalls()

        XCTAssertEqual(discardCalls, [.init(paths: ["old.swift", "new.swift"], scope: .all, directory: fixture.directory)])
    }

    func testDiscardUsesWorktreeOnlyScopeForUnstagedSelection() async throws {
        let unstagedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = TestFixture(
            gitService: MockGitService(
                statusResults: [.success([unstagedFile]), .success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        try await fixture.viewModel.discard(files: [unstagedFile], in: fixture.directory)
        let discardCalls = await fixture.gitService.discardCalls()

        XCTAssertEqual(discardCalls, [.init(paths: ["feature.swift"], scope: .worktreeOnly, directory: fixture.directory)])
    }
}

@MainActor
private struct TestFixture {
    let directory = "/tmp/skep-project"
    let gitService: MockGitService
    let gitHubService: MockGitHubService
    let fileListManager: MockFileListManager
    let agentsManager: MockAgentsManager
    let viewModel: DiffViewerViewModel

    init(
        gitService: MockGitService,
        gitHubService: MockGitHubService = MockGitHubService(),
        fileListManager: MockFileListManager = MockFileListManager(),
        agentsManager: MockAgentsManager = MockAgentsManager(),
        fsEventDebounceDuration: Duration = .milliseconds(500),
        idlePollInterval: Duration = .seconds(60)
    ) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager
        self.viewModel = DiffViewerViewModel(
            gitService: gitService,
            gitHubService: gitHubService,
            fileListManager: fileListManager,
            agentsManager: agentsManager,
            fsEventDebounceDuration: fsEventDebounceDuration,
            idlePollInterval: idlePollInterval
        )
    }
}

private actor MockGitService: GitService {
    struct DiffCall: Equatable {
        let paths: [String]
        let scope: DiffScope
        let directory: String
    }

    struct DiscardCall: Equatable {
        let paths: [String]
        let scope: DiscardScope
        let directory: String
    }

    private var statusResults: [Result<[FileStatus], Error>]
    private var diffResults: [String]
    private var diffDelays: [Duration]
    private var syntheticDiffResults: [String]
    private let currentBranchResult: Result<String, Error>
    private let commitsAheadResult: Result<Int, Error>
    private var recordedStatusCallCount = 0
    private var recordedDiffCalls: [DiffCall] = []
    private var recordedSyntheticDiffCalls: [String] = []
    private var recordedDiscardCalls: [DiscardCall] = []

    init(
        statusResults: [Result<[FileStatus], Error>],
        diffResults: [String] = [],
        diffDelays: [Duration] = [],
        syntheticDiffResults: [String] = [],
        currentBranchResult: Result<String, Error> = .success("feature"),
        commitsAheadResult: Result<Int, Error> = .success(0)
    ) {
        self.statusResults = statusResults
        self.diffResults = diffResults
        self.diffDelays = diffDelays
        self.syntheticDiffResults = syntheticDiffResults
        self.currentBranchResult = currentBranchResult
        self.commitsAheadResult = commitsAheadResult
    }

    func status(in directory: String) async throws -> [FileStatus] {
        recordedStatusCallCount += 1
        guard !statusResults.isEmpty else {
            return []
        }
        return try statusResults.removeFirst().get()
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        recordedDiffCalls.append(DiffCall(paths: paths, scope: scope, directory: directory))
        let result = diffResults.isEmpty ? "" : diffResults.removeFirst()

        if !diffDelays.isEmpty {
            let delay = diffDelays.removeFirst()
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }

        return result
    }

    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        recordedSyntheticDiffCalls.append(path)
        return syntheticDiffResults.isEmpty ? "" : syntheticDiffResults.removeFirst()
    }

    func stage(paths: [String], in directory: String) async throws {}

    func unstage(paths: [String], in directory: String) async throws {}

    func discard(paths: [String], scope: DiscardScope, in directory: String) async throws {
        recordedDiscardCalls.append(DiscardCall(paths: paths, scope: scope, directory: directory))
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        []
    }

    func currentBranch(in directory: String) async throws -> String {
        try currentBranchResult.get()
    }

    func listFiles(in directory: String) async throws -> [String] {
        []
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        try commitsAheadResult.get()
    }

    func diffCalls() -> [DiffCall] {
        recordedDiffCalls
    }

    func syntheticDiffCalls() -> [String] {
        recordedSyntheticDiffCalls
    }

    func discardCalls() -> [DiscardCall] {
        recordedDiscardCalls
    }

    func statusCallCount() -> Int {
        recordedStatusCallCount
    }
}

@MainActor
private final class MockGitHubService: GitHubService, @unchecked Sendable {
    private var listPRResults: [[PRInfo]]
    private var recordedListPRCallCount = 0

    init(listPRResults: [[PRInfo]] = [[]]) {
        self.listPRResults = listPRResults
    }

    func listPRs(in directory: String) async throws -> [PRInfo] {
        recordedListPRCallCount += 1
        if !listPRResults.isEmpty {
            return listPRResults.removeFirst()
        }
        return []
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        .none
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {}

    func listPRCallCount() -> Int {
        recordedListPRCallCount
    }
}

private actor MockFileListManager: FileListManager {
    private var recordedInvalidatedDirectories: [String] = []

    func files(for projectPath: String) async -> [String] {
        []
    }

    func invalidateCache(for projectPath: String) {
        recordedInvalidatedDirectories.append(projectPath)
    }

    func warmCache(for projectPath: String) async {}

    func invalidatedDirectories() -> [String] {
        recordedInvalidatedDirectories
    }
}

private actor MockAgentsManager: AgentsManager {
    private let statuses = LockedState<[String: ActivitySignal]>([:])

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {}

    func cancelTurn(conversationId: String) {}

    func destroyRuntime(conversationId: String) async throws {}

    func kill(conversationId: String) {}

    func killAll() {}

    func isRunning(conversationId: String) -> Bool {
        false
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        false
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        false
    }

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        statuses.withLock { $0[conversationId] ?? .neutral }
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statuses.withLock { $0 }
    }

    nonisolated func beginShutdown() {}

    nonisolated var allProcessesSnapshot: [Process] {
        []
    }
}

private extension DiffViewerViewModelTests {
    static func modifiedDiff(path: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -old
        +new
        """
    }

    static func renameDiff(from oldPath: String, to newPath: String) -> String {
        """
        diff --git a/\(oldPath) b/\(newPath)
        similarity index 100%
        rename from \(oldPath)
        rename to \(newPath)
        --- a/\(oldPath)
        +++ b/\(newPath)
        @@ -1 +1 @@
        -old
        +old
        """
    }

    static func addedDiff(path: String, content: String) -> String {
        """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,1 @@
        +\(content)
        """
    }
}
