import Foundation
import XCTest

@testable import Alveary

@MainActor
final class DiffViewerViewModelTests: XCTestCase {
    func testBackgroundWatchCallbackDispatchesRefreshToMainActor() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: Array(repeating: .success([]), count: 8)),
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: Array(repeating: .success([]), count: 6)),
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: Array(repeating: .success([]), count: 6)),
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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

    func testNonGitProjectsDoNotSurfaceDiffErrors() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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

        XCTAssertNil(fixture.viewModel.gitError)
        XCTAssertFalse(fixture.viewModel.isGitRepository)
        XCTAssertEqual(fixture.viewModel.contextualAction, .none)
        XCTAssertNil(fixture.viewModel.selectedFile)
        XCTAssertNil(fixture.viewModel.parsedDiff)
        XCTAssertEqual(diffCallCount, 1)
        XCTAssertEqual(listPRCallCount, 0)
    }

    func testSelectFileCancelsSupersededDiffLoad() async {
        let slowFile = FileStatus(path: "slow.swift", originalPath: nil, status: .modified, isStaged: false)
        let fastFile = FileStatus(path: "fast.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()

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
        let commitFixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)])]
            )
        )
        defer { commitFixture.viewModel.tearDown() }
        await assertContextualAction(.commit, in: commitFixture, baseRef: "main", remoteName: nil)

        let viewPRFixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            ),
            gitHubService: DiffViewerMockGitHubService(
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
        await assertContextualAction(.viewPR(url: "https://example.com/42"), in: viewPRFixture, baseRef: "main", remoteName: "origin")

        let openPRFixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(2)
            )
        )
        defer { openPRFixture.viewModel.tearDown() }
        await assertContextualAction(.openPR, in: openPRFixture, baseRef: "main", remoteName: "origin")
    }

    func testRefreshAndInvalidateFileListPreservesWarmPRCacheForLocalGitMutations() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([]), .success([])],
                currentBranchResult: .success("feature"),
                commitsAheadResult: .success(0)
            ),
            gitHubService: DiffViewerMockGitHubService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
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

extension DiffViewerViewModelTests {
    func assertContextualAction(
        _ expectedAction: DiffViewerViewModel.ContextualAction,
        in fixture: DiffViewerTestFixture,
        baseRef: String,
        remoteName: String?
    ) async {
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: baseRef,
            remoteName: remoteName,
            conversationIds: []
        )

        XCTAssertEqual(fixture.viewModel.contextualAction, expectedAction)
    }

    static func modifiedDiff(path: String, newLine: String = "new") -> String {
        """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -old
        +\(newLine)
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
