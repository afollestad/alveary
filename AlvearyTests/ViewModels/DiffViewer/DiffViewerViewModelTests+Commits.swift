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
        XCTAssertEqual(fixture.viewModel.selectedCommits, [commits[0]])
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
        XCTAssertEqual(fixture.viewModel.selectedCommits, [commit])
        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: "0:Sources/App.swift")
        XCTAssertFalse(fixture.viewModel.selectedCommitCollapsedFileIDs.isEmpty)

        await fixture.viewModel.switchToDirectory(
            "/tmp/alveary-other-project",
            baseRef: "main",
            remoteName: "origin",
            conversationIds: []
        )

        XCTAssertTrue(fixture.viewModel.aheadCommits.isEmpty)
        XCTAssertNil(fixture.viewModel.selectedCommit)
        XCTAssertTrue(fixture.viewModel.selectedCommits.isEmpty)
        XCTAssertTrue(fixture.viewModel.commitDiffFiles.isEmpty)
        XCTAssertTrue(fixture.viewModel.rawCommitDiffContent.isEmpty)
        XCTAssertEqual(fixture.viewModel.commitsLoadState, DiffWorkspaceLoadState.idle)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.idle)
        XCTAssertTrue(fixture.viewModel.selectedCommitCollapsedFileIDs.isEmpty)
        XCTAssertTrue(fixture.viewModel.collapsedCommitFileIDsByCommitHash.isEmpty)
    }

    func testRefreshRevisionAllowsCommitModeToReloadAheadCommitsAfterRepositoryChanges() async {
        let commit = Self.commit(hash: "abcdef1234567890", message: "Add Git service update")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [.success([]), .success([commit])],
                commitDiffResults: [.success(Self.modifiedDiff(path: "Alveary/Services/Git/CLIGitService.swift"))]
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

        XCTAssertTrue(fixture.viewModel.aheadCommits.isEmpty)
        let previousRevision = fixture.viewModel.workspaceRefreshRevision

        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)
        XCTAssertGreaterThan(fixture.viewModel.workspaceRefreshRevision, previousRevision)

        XCTAssertEqual(fixture.viewModel.aheadCommits, [commit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map { $0.path }, ["Alveary/Services/Git/CLIGitService.swift"])
    }

    func testLargeCommitDiffParsesWithoutPreviewLineCap() async {
        let commit = Self.commit(hash: "abcdef1234567890", message: "Large commit")
        let largeDiff = Self.modifiedDiff(path: "Large.swift")
            + "\n"
            + Array(repeating: " context", count: 1_001).joined(separator: "\n")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([commit])],
                commitDiffResults: [.success(largeDiff)]
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
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Large.swift"])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.first?.hunks.first?.lines.count, 1_003)
        XCTAssertEqual(fixture.viewModel.selectedCommitDiffLoadState, DiffWorkspaceLoadState.loaded)
        XCTAssertNil(fixture.viewModel.selectedCommitDiffErrorMessage)
    }

    func testCommitFileCollapseStartsExpandedAfterLoadingCommitDiff() async {
        let commit = Self.commit(hash: "abcdef1234567890", message: "Add commit mode")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
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
        XCTAssertTrue(fixture.viewModel.selectedCommitCollapsedFileIDs.isEmpty)
    }

    func testToggleCommitFileCollapseRecordsStateForSelectedCommit() async {
        let commit = Self.commit(hash: "abcdef1234567890", message: "Add commit mode")
        let fileID = "0:Sources/App.swift"
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
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

        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: fileID)
        XCTAssertEqual(fixture.viewModel.selectedCommitCollapsedFileIDs, [fileID])

        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: fileID)
        XCTAssertTrue(fixture.viewModel.selectedCommitCollapsedFileIDs.isEmpty)
        XCTAssertTrue(fixture.viewModel.collapsedCommitFileIDsByCommitHash.isEmpty)
    }

    func testCommitFileCollapseStateIsSeparatePerSelectedCommit() async {
        let firstCommit = Self.commit(hash: "abcdef1234567890", message: "First commit")
        let secondCommit = Self.commit(hash: "1234567890abcdef", message: "Second commit")
        let firstFileID = "0:Sources/First.swift"
        let secondFileID = "0:Sources/Second.swift"
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success([firstCommit, secondCommit])],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/First.swift")),
                    .success(Self.modifiedDiff(path: "Sources/Second.swift")),
                    .success(Self.modifiedDiff(path: "Sources/First.swift"))
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

        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: firstFileID)
        XCTAssertEqual(fixture.viewModel.selectedCommitCollapsedFileIDs, [firstFileID])

        await fixture.viewModel.selectCommit(secondCommit)
        XCTAssertTrue(fixture.viewModel.selectedCommitCollapsedFileIDs.isEmpty)

        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: secondFileID)
        XCTAssertEqual(fixture.viewModel.selectedCommitCollapsedFileIDs, [secondFileID])

        await fixture.viewModel.selectCommit(firstCommit)
        XCTAssertEqual(fixture.viewModel.selectedCommitCollapsedFileIDs, [firstFileID])
    }

    func testCommitRefreshPrunesCollapseStateForCommitsNoLongerAhead() async {
        let firstCommit = Self.commit(hash: "abcdef1234567890", message: "First commit")
        let secondCommit = Self.commit(hash: "1234567890abcdef", message: "Second commit")
        let firstFileID = "0:Sources/First.swift"
        let secondFileID = "0:Sources/Second.swift"
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([]), .success([])],
                commitsAheadDetailsResults: [
                    .success([firstCommit, secondCommit]),
                    .success([firstCommit])
                ],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "Sources/First.swift")),
                    .success(Self.modifiedDiff(path: "Sources/Second.swift")),
                    .success(Self.modifiedDiff(path: "Sources/First.swift"))
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
        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: firstFileID)

        await fixture.viewModel.selectCommit(secondCommit)
        fixture.viewModel.toggleSelectedCommitFileCollapse(fileID: secondFileID)
        await fixture.viewModel.refresh(in: fixture.directory, reason: .localGitMutation)

        XCTAssertEqual(Set(fixture.viewModel.collapsedCommitFileIDsByCommitHash.keys), [firstCommit.hash])
        XCTAssertEqual(fixture.viewModel.selectedCommit, firstCommit)
        XCTAssertEqual(fixture.viewModel.selectedCommitCollapsedFileIDs, [firstFileID])
    }

    func testKeyboardNavigationMovesSelectedCommitAndLoadsDiff() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "First commit"),
            Self.commit(hash: "1234567890abcdef", message: "Second commit"),
            Self.commit(hash: "fedcba0987654321", message: "Third commit")
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success(commits)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "First.swift")),
                    .success(Self.modifiedDiff(path: "Second.swift")),
                    .success(Self.modifiedDiff(path: "First.swift"))
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

        await fixture.viewModel.selectAdjacentCommit(forward: true)

        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[1])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Second.swift"])

        await fixture.viewModel.selectAdjacentCommit(forward: false)

        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[0])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["First.swift"])
    }

    func testAdjacentCommitUsesProvidedAnchorForFastRepeat() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "First commit"),
            Self.commit(hash: "1234567890abcdef", message: "Second commit"),
            Self.commit(hash: "fedcba0987654321", message: "Third commit")
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success(commits)],
                commitDiffResults: [.success(Self.modifiedDiff(path: "First.swift"))]
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

        XCTAssertEqual(fixture.viewModel.adjacentCommit(from: commits[0].id, forward: true), commits[1])
        XCTAssertEqual(fixture.viewModel.adjacentCommit(from: commits[1].id, forward: true), commits[2])
        XCTAssertEqual(fixture.viewModel.adjacentCommit(from: commits[1].id, forward: false), commits[0])
        XCTAssertNil(fixture.viewModel.adjacentCommit(from: commits[2].id, forward: true))
    }

    func testKeyboardNavigationAtCommitBoundsDoesNotChangeSelection() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "First commit"),
            Self.commit(hash: "1234567890abcdef", message: "Second commit")
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success(commits)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "First.swift")),
                    .success(Self.modifiedDiff(path: "Second.swift"))
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

        await fixture.viewModel.selectAdjacentCommit(forward: false)

        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[0])

        await fixture.viewModel.selectAdjacentCommit(forward: true)
        await fixture.viewModel.selectAdjacentCommit(forward: true)

        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[1])

        let diffCalls = await fixture.gitService.commitDiffCalls()
        XCTAssertEqual(diffCalls.map(\.hash), [commits[0].hash, commits[1].hash])
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

    static func commit(hash: String, message: String) -> CommitInfo {
        CommitInfo(hash: hash, message: message, author: "A. Developer", date: Date(timeIntervalSince1970: 1_800_000_000))
    }
}
