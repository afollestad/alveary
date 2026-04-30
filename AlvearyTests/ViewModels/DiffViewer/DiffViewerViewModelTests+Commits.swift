import Foundation
import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testLoadAheadCommitsAutoSelectsFirstCommitAndParsesDiff() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "Add commit mode"),
            Self.commit(hash: "1234567890abcdef", message: "Polish diff rows")
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success(commits)],
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

        XCTAssertEqual(fixture.viewModel.aheadCommits, commits)
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[0])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map { $0.path }, ["Sources/App.swift"])
        XCTAssertTrue(fixture.viewModel.rawCommitDiffContent.contains("Sources/App.swift"))
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.loaded)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)

        let detailCalls = await fixture.gitService.commitsAheadDetailsCalls()
        let diffCalls = await fixture.gitService.commitDiffCalls()
        XCTAssertEqual(detailCalls.map { $0.baseBranch }, ["main"])
        XCTAssertEqual(detailCalls.map { $0.remoteName }, ["origin"])
        XCTAssertEqual(diffCalls.map { $0.hash }, ["abcdef1234567890"])
    }

    func testSwitchingTargetsClearsCommitState() async {
        let commit = Self.commit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([commit])],
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

        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)

        await fixture.viewModel.switchToDirectory(
            "/tmp/alveary-other-project",
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )

        XCTAssertTrue(fixture.viewModel.aheadCommits.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedCommit)
        XCTAssertTrue(fixture.viewModel.commitDiffFiles.isEmpty)
        XCTAssertTrue(fixture.viewModel.rawCommitDiffContent.isEmpty)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.idle)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.idle)
    }

    func testDelayedCommitListDoesNotPublishAfterTargetSwitch() async {
        let staleCommit = Self.commit(hash: "abcdef1234567890", message: "Stale result")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([staleCommit])],
                commitsAheadDetailsDelays: [.milliseconds(250)]
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
        await fixture.viewModel.switchToDirectory(
            "/tmp/alveary-other-project",
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )
        await loadTask.value

        XCTAssertTrue(fixture.viewModel.aheadCommits.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedCommit)
        XCTAssertTrue(fixture.viewModel.commitDiffFiles.isEmpty)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.idle)
    }

    func testSelectingCommitCancelsStaleDiffPublish() async {
        let slowCommit = Self.commit(hash: "abcdef1234567890", message: "Slow patch")
        let fastCommit = Self.commit(hash: "1234567890abcdef", message: "Fast patch")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([slowCommit, fastCommit])],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Slow.swift", newLine: "slow")),
                    .success(Self.modifiedDiff(path: "Fast.swift", newLine: "fast"))
                ],
                commitDiffDelays: [.milliseconds(250), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: Optional<String>.none,
            conversationIds: []
        )
        let loadTask = Task {
            await fixture.viewModel.loadAheadCommitsForActiveTarget()
        }

        try? await Task.sleep(for: .milliseconds(50))
        await fixture.viewModel.selectCommit(fastCommit)
        await loadTask.value

        XCTAssertEqual(fixture.viewModel.selectedCommit, fastCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map { $0.path }, ["Fast.swift"])
        XCTAssertFalse(fixture.viewModel.rawCommitDiffContent.contains("Slow.swift"))
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)
    }

    private static func commit(hash: String, message: String) -> CommitInfo {
        CommitInfo(hash: hash, message: message, author: "A. Developer", date: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
