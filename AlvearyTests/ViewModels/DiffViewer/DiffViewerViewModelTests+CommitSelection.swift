import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testSelectAllCommitsSelectsEveryCommitAndPreservesPreviewAnchor() async {
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
        await fixture.viewModel.selectCommit(commits[1])

        await fixture.viewModel.selectAllCommits()

        XCTAssertEqual(fixture.viewModel.selectedCommits, commits)
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[1])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Second.swift"])
    }

    func testPlainCommitSelectionClearsMultiSelection() async {
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
        await fixture.viewModel.selectAllCommits()

        await fixture.viewModel.selectCommit(commits[1])

        XCTAssertEqual(fixture.viewModel.selectedCommits, [commits[1]])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[1])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Second.swift"])
    }

    func testCommitModifierAndRangeSelectionMatchesFileSelection() async {
        let commits = [
            Self.commit(hash: "abcdef1234567890", message: "First commit"),
            Self.commit(hash: "1234567890abcdef", message: "Second commit"),
            Self.commit(hash: "fedcba0987654321", message: "Third commit"),
            Self.commit(hash: "0987654321fedcba", message: "Fourth commit")
        ]
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [.success(commits)],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "First.swift")),
                    .success(Self.modifiedDiff(path: "Third.swift")),
                    .success(Self.modifiedDiff(path: "Fourth.swift"))
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

        await fixture.viewModel.selectCommit(commits[2], behavior: .toggle)

        XCTAssertEqual(fixture.viewModel.selectedCommits, [commits[0], commits[2]])
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[2])

        await fixture.viewModel.selectCommit(commits[3], behavior: .range)

        XCTAssertEqual(fixture.viewModel.selectedCommits, Array(commits[2...3]))
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[3])

        await fixture.viewModel.selectCommit(commits[0], behavior: .rangeUnion)

        XCTAssertEqual(fixture.viewModel.selectedCommits, commits)
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[0])
    }

    func testKeyboardRangeNavigationExtendsCommitSelection() async {
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
                    .success(Self.modifiedDiff(path: "Third.swift"))
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

        guard let secondCommit = fixture.viewModel.adjacentCommit(from: fixture.viewModel.selectedCommit?.id, forward: true) else {
            XCTFail("Expected second commit")
            return
        }
        await fixture.viewModel.selectCommit(secondCommit, behavior: .range)

        XCTAssertEqual(fixture.viewModel.selectedCommits, Array(commits[0...1]))
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[1])

        guard let thirdCommit = fixture.viewModel.adjacentCommit(from: fixture.viewModel.selectedCommit?.id, forward: true) else {
            XCTFail("Expected third commit")
            return
        }
        await fixture.viewModel.selectCommit(thirdCommit, behavior: .range)

        XCTAssertEqual(fixture.viewModel.selectedCommits, commits)
        XCTAssertEqual(fixture.viewModel.selectedCommit, commits[2])
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Third.swift"])
    }

    func testCommitListRefreshPrunesSelectedCommits() async {
        let firstCommit = Self.commit(hash: "abcdef1234567890", message: "First commit")
        let secondCommit = Self.commit(hash: "1234567890abcdef", message: "Second commit")
        let thirdCommit = Self.commit(hash: "fedcba0987654321", message: "Third commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [
                    .success([firstCommit, secondCommit, thirdCommit]),
                    .success([secondCommit])
                ],
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
        await fixture.viewModel.selectAllCommits()

        guard let target = fixture.viewModel.diffStore.activeTarget else {
            XCTFail("Expected an active diff target")
            return
        }
        await fixture.viewModel.loadAheadCommits(for: target, preservesSelectedDiff: true, forceReload: true)

        XCTAssertEqual(fixture.viewModel.aheadCommits, [secondCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommits, [secondCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, secondCommit)
    }

    func testCommitListRefreshKeepsRemainingSelectedCommitAsPreviewWhenPreviewCommitIsRemoved() async {
        let firstCommit = Self.commit(hash: "abcdef1234567890", message: "First commit")
        let secondCommit = Self.commit(hash: "1234567890abcdef", message: "Second commit")
        let thirdCommit = Self.commit(hash: "fedcba0987654321", message: "Third commit")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                commitsAheadDetailsResults: [
                    .success([firstCommit, secondCommit, thirdCommit]),
                    .success([secondCommit, thirdCommit])
                ],
                commitDiffResults: [
                    .success(Self.modifiedDiff(path: "First.swift")),
                    .success(Self.modifiedDiff(path: "Third.swift")),
                    .success(Self.modifiedDiff(path: "Third.swift"))
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
        await fixture.viewModel.selectCommit(thirdCommit, behavior: .toggle)

        guard let target = fixture.viewModel.diffStore.activeTarget else {
            XCTFail("Expected an active diff target")
            return
        }
        await fixture.viewModel.loadAheadCommits(for: target, preservesSelectedDiff: true, forceReload: true)

        XCTAssertEqual(fixture.viewModel.selectedCommits, [thirdCommit])
        XCTAssertEqual(fixture.viewModel.selectedCommit, thirdCommit)
        XCTAssertEqual(fixture.viewModel.commitDiffFiles.map(\.path), ["Third.swift"])
    }
}
