import XCTest

@testable import Alveary

/// `DiffViewerWorkingState` publishing: the footer ladder's dirty/unpushed flags
/// and the header's branch label, all resolved by the same guarded probe on
/// `performRefresh`. Split out of `DiffViewerViewModelTests.swift` to keep that
/// file under the length limit.
@MainActor
extension DiffViewerViewModelTests {
    func testWorkingStateReportsChangesOnlyWhenFilesChanged() async {
        let commitFixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)])]
            )
        )
        defer { commitFixture.viewModel.tearDown() }
        await assertWorkingState(
            DiffViewerWorkingState(hasChanges: true, currentBranch: "feature"),
            in: commitFixture,
            baseRef: "main",
            remoteName: nil
        )

        let cleanFixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])]
            )
        )
        defer { cleanFixture.viewModel.tearDown() }
        await assertWorkingState(
            DiffViewerWorkingState(currentBranch: "feature"),
            in: cleanFixture,
            baseRef: "main",
            remoteName: "origin"
        )
    }

    /// The refresh's unpushed probe is what walks the footer's button from
    /// Commit to Push changes once the tree is clean but the remote is behind.
    func testWorkingStateReportsUnpushedCommits() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                hasUnpushedCommitsResult: .success(true)
            )
        )
        defer { fixture.viewModel.tearDown() }

        await assertWorkingState(
            DiffViewerWorkingState(hasChanges: false, hasUnpushedCommits: true, currentBranch: "feature"),
            in: fixture,
            baseRef: "main",
            remoteName: "origin"
        )
    }

    /// The flag is informational, so a failed probe reads as nothing to push
    /// rather than surfacing an error.
    func testWorkingStateTreatsAFailedUnpushedProbeAsNothingToPush() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                hasUnpushedCommitsResult: .failure(GitError.commandFailed("probe failed"))
            )
        )
        defer { fixture.viewModel.tearDown() }

        await assertWorkingState(
            DiffViewerWorkingState(currentBranch: "feature"),
            in: fixture,
            baseRef: "main",
            remoteName: "origin"
        )
    }

    /// The header names the checked-out branch, published by the same guarded
    /// probe as the footer's flags so the two can never disagree.
    func testWorkingStatePublishesCurrentBranch() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("alveary/long-feature-branch")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await assertWorkingState(
            DiffViewerWorkingState(currentBranch: "alveary/long-feature-branch"),
            in: fixture,
            baseRef: "main",
            remoteName: "origin"
        )
    }

    /// `git rev-parse --abbrev-ref HEAD` prints the literal `HEAD` on a detached
    /// checkout, which is a worse header label than none at all.
    func testWorkingStateDropsDetachedHeadAsBranchName() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                currentBranchResult: .success("HEAD")
            )
        )
        defer { fixture.viewModel.tearDown() }

        await assertWorkingState(.none, in: fixture, baseRef: "main", remoteName: "origin")
    }

    /// The branch is informational like the unpushed flag, so a failed probe
    /// simply omits the label rather than surfacing an error.
    func testWorkingStateTreatsAFailedBranchProbeAsNoBranch() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                currentBranchResult: .failure(GitError.commandFailed("probe failed"))
            )
        )
        defer { fixture.viewModel.tearDown() }

        await assertWorkingState(.none, in: fixture, baseRef: "main", remoteName: "origin")
    }

    func assertWorkingState(
        _ expectedState: DiffViewerWorkingState,
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

        XCTAssertEqual(fixture.viewModel.workingState, expectedState)
    }
}
