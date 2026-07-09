import XCTest

@testable import Alveary

// swiftlint:disable function_body_length

@MainActor
extension DiffViewerViewModelTests {
    func testProjectSwitchClearsVisibleStatsWithoutDroppingCachedStats() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let projectStats = DiffStats(additions: 12, deletions: 3)
        let secondProjectStats = DiffStats(additions: 4, deletions: 1)
        let refreshedProjectStats = DiffStats(additions: 15, deletions: 5)
        let secondDirectory = storeFixtureDirectory("second")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .milliseconds(120), .milliseconds(120)],
                diffStatsResults: [
                    .success(projectStats),
                    .success(secondProjectStats),
                    .success(refreshedProjectStats)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, projectStats)

        let secondStatusEntered = expectation(description: "second project status entered")
        await fixture.gitService.setOnStatus { secondStatusEntered.fulfill() }
        let secondSwitchTask = Task {
            await fixture.viewModel.switchToDirectory(
                secondDirectory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [secondStatusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await secondSwitchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, secondProjectStats)

        let firstStatusEntered = expectation(description: "first project status entered again")
        await fixture.gitService.setOnStatus { firstStatusEntered.fulfill() }
        let firstSwitchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [firstStatusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, projectStats)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await firstSwitchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedProjectStats)
    }

    func testProjectAndWorktreeUseSeparateDiffStatsCacheEntries() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let projectStats = DiffStats(additions: 7, deletions: 1)
        let worktreeStats = DiffStats(additions: 21, deletions: 8)
        let refreshedProjectStats = DiffStats(additions: 9, deletions: 2)
        let projectTarget = storeDiffTarget(
            projectPath: storeFixtureDirectory("base"),
            worktreePath: nil
        )
        let worktreeTarget = storeDiffTarget(
            projectPath: projectTarget.projectPath,
            worktreePath: storeFixtureDirectory("worktree")
        )
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .zero, .milliseconds(120)],
                diffStatsResults: [
                    .success(projectStats),
                    .success(worktreeStats),
                    .success(refreshedProjectStats)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToTarget(projectTarget)
        await fixture.diffStore.waitForStatsForTesting()
        await fixture.viewModel.switchToTarget(worktreeTarget)
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, worktreeStats)

        let projectStatusEntered = expectation(description: "project status entered")
        await fixture.gitService.setOnStatus { projectStatusEntered.fulfill() }
        let projectSwitchTask = Task {
            await fixture.viewModel.switchToTarget(projectTarget)
        }

        await fulfillment(of: [projectStatusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, projectStats)

        await projectSwitchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedProjectStats)
    }

    func testUncachedTargetLoadsStatsAfterStatusPublishes() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                statusDelays: [.milliseconds(120)],
                diffStatsResults: [.success(DiffStats(additions: 5, deletions: 1))],
                diffStatsDelays: [.milliseconds(120)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        let statusEntered = expectation(description: "status entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }
        let diffStatsEntered = expectation(description: "diff stats entered")
        await fixture.gitService.setOnDiffStats { diffStatsEntered.fulfill() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)
        let diffStatsCallCountBeforeStatusCompleted = await fixture.gitService.diffStatsCallCount()
        XCTAssertEqual(diffStatsCallCountBeforeStatusCompleted, 0)

        await switchTask.value
        XCTAssertEqual(fixture.viewModel.files, [modifiedFile])
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)
        await fulfillment(of: [diffStatsEntered], timeout: 2.0)
        let diffStatsCallCountAfterStatusCompleted = await fixture.gitService.diffStatsCallCount()
        XCTAssertEqual(diffStatsCallCountAfterStatusCompleted, 1)

        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
        XCTAssertEqual(fixture.viewModel.diffStats, DiffStats(additions: 5, deletions: 1))
    }

    func testStaleStatsLoadCannotPublishAfterTargetSwitch() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let staleStats = DiffStats(additions: 99, deletions: 99)
        let currentStats = DiffStats(additions: 2, deletions: 1)
        let secondDirectory = storeFixtureDirectory("second")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                diffStatsResults: [
                    .success(staleStats),
                    .success(currentStats)
                ],
                diffStatsDelays: [.milliseconds(180), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await fixture.viewModel.switchToDirectory(
            secondDirectory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, currentStats)

        try? await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(fixture.viewModel.diffStats, currentStats)
    }

    func testTargetSwitchRestartsToolbarSpinnerGracePeriod() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let firstDirectory = storeFixtureDirectory("first")
        let secondDirectory = storeFixtureDirectory("second")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                diffStatsResults: [
                    .success(DiffStats(additions: 1, deletions: 1)),
                    .success(DiffStats(additions: 2, deletions: 2))
                ],
                diffStatsDelays: [.milliseconds(120), .milliseconds(120)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            firstDirectory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        let secondStatusEntered = expectation(description: "second target status entered")
        await fixture.gitService.setOnStatus { secondStatusEntered.fulfill() }
        let secondSwitchTask = Task {
            await fixture.viewModel.switchToDirectory(
                secondDirectory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [secondStatusEntered], timeout: 2.0)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)

        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await secondSwitchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
    }

    func testSupersededStatsCancellationDoesNotClearNewerStatsLoad() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let refreshedStats = DiffStats(additions: 3, deletions: 1)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                diffStatsResults: [
                    .success(DiffStats(additions: 99, deletions: 99)),
                    .success(refreshedStats)
                ],
                diffStatsDelays: [.milliseconds(180), .milliseconds(120)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(fixture.viewModel.diffStatsLoadState, .loading)
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedStats)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
    }

    private func storeFixtureDirectory(_ suffix: String) -> String {
        "/tmp/alveary-project-\(suffix)"
    }

    private func storeDiffTarget(projectPath: String, worktreePath: String?) -> DiffViewerSwitchTarget {
        DiffViewerSwitchTarget(
            projectPath: projectPath,
            worktreePath: worktreePath,
            directory: worktreePath ?? projectPath,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
    }
}

// swiftlint:enable function_body_length
