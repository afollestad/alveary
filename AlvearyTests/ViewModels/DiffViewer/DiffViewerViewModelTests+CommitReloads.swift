import Foundation
import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testCommitReloadDuringSelectedDiffLoadIsCoalesced() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Large commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([commit]), .success([commit])],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Slow.swift", newLine: "slow"))
                ],
                commitDiffDelays: [.milliseconds(150), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        let loadTask = Task {
            await fixture.viewModel.loadAheadCommitsForActiveTarget()
        }

        try? await Task.sleep(for: .milliseconds(50))
        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loading)
        await loadTask.value

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        let diffCalls = await fixture.gitService.commitDiffCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(diffCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Slow.swift"])
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)
    }

    func testDuplicateSameTargetCommitLoadsAreIgnored() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([commit]), .success([commit])],
                commitsAheadDetailsDelays: [.milliseconds(150)],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )

        async let firstLoad: Void = fixture.viewModel.loadAheadCommitsForActiveTarget()
        try? await Task.sleep(for: .milliseconds(30))
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        await firstLoad

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)
    }

    func testThreadSwitchRefreshDoesNotDuplicateInitialCommitLoad() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                statusDelays: [.milliseconds(150)],
                commitsAheadDetailsResults: [.success([commit]), .success([commit])],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: "origin",
                conversationIds: []
            )
        }

        try? await Task.sleep(for: .milliseconds(30))
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        await switchTask.value

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/App.swift"])
    }

    func testSameTargetWorkspaceRefreshPreservesVisibleCommitUIWhileReloading() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([commit]), .success([commit])],
                commitsAheadDetailsDelays: [.zero, .milliseconds(150)],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)

        let refreshTask = Task {
            await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loading)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)

        await refreshTask.value

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        let diffCalls = await fixture.gitService.commitDiffCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(diffCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loaded)
    }

    func testSameTargetWorkspaceRefreshFailurePreservesVisibleCommitState() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([commit]), .failure(GitError.commandFailed("git failed"))],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.failed)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)
    }

    func testSameTargetRetryAfterFailedRefreshPreservesVisibleCommitStateWhileReloading() async {
        let oldCommit = Self.reloadCommit(hash: "abcdef1234567890", message: "Old commit")
        let newCommit = Self.reloadCommit(hash: "1234567890abcdef", message: "New commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [
                    .success([oldCommit]),
                    .failure(GitError.commandFailed("git failed")),
                    .success([newCommit])
                ],
                commitsAheadDetailsDelays: [.zero, .zero, .milliseconds(150)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/Old.swift")),
                    .success(Self.modifiedDiff(path: "Sources/New.swift"))
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
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        let retryTask = Task {
            await fixture.viewModel.loadAheadCommitsForActiveTarget()
        }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loading)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [oldCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, oldCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/Old.swift"])

        await retryTask.value

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 3)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loaded)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [newCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, newCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/New.swift"])
    }

    func testActiveWorkspaceRefreshRetriesFailedCommitListWithoutRows() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Recovered commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [
                    .failure(GitError.commandFailed("git failed")),
                    .success([commit])
                ],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.failed)
        XCTAssertTrue(fixture.viewModel.aheadCommits.isEmpty)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loaded)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/App.swift"])
    }

    func testManualCommitSelectionDuringReloadDoesNotStrandListLoad() async {
        let firstCommit = Self.reloadCommit(hash: "abcdef1234567890", message: "First commit")
        let oldSecondCommit = Self.reloadCommit(hash: "1234567890abcdef", message: "Old second commit")
        let updatedSecondCommit = Self.reloadCommit(hash: oldSecondCommit.hash, message: "Updated second commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [
                    .success([firstCommit, oldSecondCommit]),
                    .success([updatedSecondCommit])
                ],
                commitsAheadDetailsDelays: [.zero, .milliseconds(150)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/First.swift")),
                    .success(Self.modifiedDiff(path: "Sources/Second.swift"))
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
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        let refreshTask = Task {
            await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        }
        try? await Task.sleep(for: .milliseconds(50))
        await fixture.viewModel.selectCommit(oldSecondCommit)
        await refreshTask.value

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        let diffCalls = await fixture.gitService.commitDiffCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(diffCalls.map(\.hash), [firstCommit.hash, oldSecondCommit.hash])
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loaded)
        XCTAssertNil(fixture.viewModel.inFlightCommitListLoad)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [updatedSecondCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, updatedSecondCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/Second.swift"])
    }

    func testWorkspaceRefreshDoesNotReloadCommitsWhenCommitModeIsInactive() async {
        let commit = Self.reloadCommit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([commit]), .success([commit])],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Sources/App.swift"))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        fixture.viewModel.setCommitModeActive(false)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
    }

    func testInactiveWorkspaceRefreshReloadsWhenCommitModeBecomesActiveAgain() async {
        let oldCommit = Self.reloadCommit(hash: "abcdef1234567890", message: "Old commit")
        let newCommit = Self.reloadCommit(hash: "1234567890abcdef", message: "New commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([oldCommit]), .success([newCommit])],
                commitsAheadDetailsDelays: [.zero, .milliseconds(150)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/Old.swift")),
                    .success(Self.modifiedDiff(path: "Sources/New.swift"))
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
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        fixture.viewModel.setCommitModeActive(false)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        var detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 1)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [oldCommit])

        let reloadTask = Task {
            await fixture.viewModel.loadAheadCommitsForActiveTarget()
        }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loading)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [oldCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, oldCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/Old.swift"])

        await reloadTask.value

        detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [newCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, newCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/New.swift"])
    }

    func testInactiveStatusFailureMarksCommitListStaleForNextActivation() async {
        let oldCommit = Self.reloadCommit(hash: "abcdef1234567890", message: "Old commit")
        let newCommit = Self.reloadCommit(hash: "1234567890abcdef", message: "New commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .failure(GitError.commandFailed("status failed"))],
                commitsAheadDetailsResults: [.success([oldCommit]), .success([newCommit])],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/Old.swift")),
                    .success(Self.modifiedDiff(path: "Sources/New.swift"))
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
        await fixture.viewModel.loadAheadCommitsForActiveTarget()
        fixture.viewModel.setCommitModeActive(false)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [newCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, newCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Sources/New.swift"])
    }

    func testPendingCommitReloadDiscardedWhenInactiveReloadsOnNextActivation() async {
        let oldCommit = Self.reloadCommit(hash: "abcdef1234567890", message: "Large commit")
        let newCommit = Self.reloadCommit(hash: "1234567890abcdef", message: "Updated commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([oldCommit]), .success([newCommit])],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Slow.swift", newLine: "slow")),
                    .success(Self.modifiedDiff(path: "Updated.swift", newLine: "updated"))
                ],
                commitDiffDelays: [.milliseconds(150)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        let loadTask = Task {
            await fixture.viewModel.loadAheadCommitsForActiveTarget()
        }

        try? await Task.sleep(for: .milliseconds(50))
        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        fixture.viewModel.setCommitModeActive(false)
        await loadTask.value

        var detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 1)
        XCTAssertNil(fixture.viewModel.pendingCommitReloadTarget)
        XCTAssertTrue(fixture.viewModel.isCommitListRefreshNeeded)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Slow.swift"])

        await fixture.viewModel.loadAheadCommitsForActiveTarget()

        detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        XCTAssertEqual(detailCalls.count, 2)
        XCTAssertEqual(fixture.viewModel.aheadCommits, [newCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, newCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Updated.swift"])
    }

    func testLeavingCommitModeWithoutPendingReloadDoesNotMarkCommitListStale() {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(statusResults: [.success([])])
        )
        defer { fixture.viewModel.tearDown() }

        fixture.viewModel.setCommitModeActive(false)

        XCTAssertFalse(fixture.viewModel.isCommitListRefreshNeeded)
    }

    private static func reloadCommit(hash: String, message: String) -> CommitInfo {
        CommitInfo(hash: hash, message: message, author: "A. Developer", date: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
