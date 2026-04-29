import XCTest

@testable import Alveary

// swiftlint:disable function_body_length

@MainActor
extension DiffViewerViewModelTests {
    func testRefreshPublishesDiffStats() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                diffStatsResults: [.success(DiffStats(additions: 12, deletions: 3))]
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

        XCTAssertEqual(fixture.viewModel.diffStats, DiffStats(additions: 12, deletions: 3))
    }

    func testRefreshKeepsStatusWhenDiffStatsFail() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                diffStatsResults: [.failure(GitError.commandFailed("bad numstat"))]
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

        XCTAssertEqual(fixture.viewModel.files, [modifiedFile])
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)
        XCTAssertNil(fixture.viewModel.gitError)
        XCTAssertEqual(fixture.viewModel.diffStatsLoadState, .failed)
    }

    func testStatsFailureEvictsOnlyCurrentTargetCache() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let initialStats = DiffStats(additions: 11, deletions: 2)
        let secondStats = DiffStats(additions: 4, deletions: 1)
        let refreshedStats = DiffStats(additions: 13, deletions: 3)
        let secondDirectory = fixtureDirectory("second")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .zero, .zero, .milliseconds(120)],
                diffStatsResults: [
                    .success(initialStats),
                    .failure(GitError.commandFailed("bad numstat")),
                    .success(secondStats),
                    .success(refreshedStats)
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(fixture.directory, remoteName: nil, conversationIds: [])
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, initialStats)

        await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)

        await fixture.viewModel.switchToDirectory(secondDirectory, remoteName: nil, conversationIds: [])
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, secondStats)

        let statusEntered = expectation(description: "status entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }
        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(fixture.directory, remoteName: nil, conversationIds: [])
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)

        await switchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedStats)
    }

    func testQuickSelectedDiffDoesNotShowToolbarSpinner() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                diffStatsResults: [.success(DiffStats(additions: 5, deletions: 1))],
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
        await fixture.diffStore.waitForStatsForTesting()

        await fixture.viewModel.selectFile(modifiedFile, in: fixture.directory)

        XCTAssertFalse(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
    }

    func testDelayedSelectedDiffLoadingContributesToToolbarLoading() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                diffStatsResults: [.success(DiffStats(additions: 5, deletions: 1))],
                diffResults: [Self.modifiedDiff(path: "feature.swift")],
                diffDelays: [.milliseconds(120)]
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
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)

        let selectionTask = Task {
            await fixture.viewModel.selectFile(modifiedFile, in: fixture.directory)
        }

        XCTAssertFalse(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)

        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertTrue(fixture.viewModel.isDiffToolbarLoading)

        await selectionTask.value
        XCTAssertFalse(fixture.viewModel.isDiffToolbarLoading)
    }

    func testSelectedDiffFailureClearsLoadingState() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([modifiedFile])],
                diffStatsResults: [.success(DiffStats(additions: 5, deletions: 1))],
                diffResultQueue: [.failure(GitError.commandFailed("bad diff"))],
                diffDelays: [.milliseconds(120)]
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

        let selectionTask = Task {
            await fixture.viewModel.selectFile(modifiedFile, in: fixture.directory)
        }

        await fixture.diffStore.waitForLoadingIndicatorsForTesting()
        XCTAssertTrue(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertTrue(fixture.viewModel.isSelectedDiffPending)

        await selectionTask.value

        XCTAssertFalse(fixture.viewModel.isLoadingSelectedDiff)
        XCTAssertFalse(fixture.viewModel.isSelectedDiffPending)
        XCTAssertNil(fixture.viewModel.parsedDiff)
        XCTAssertEqual(fixture.viewModel.rawDiffContent, "")
        XCTAssertEqual(fixture.viewModel.gitError, "Diff failed: bad diff")
    }

    func testDirectorySwitchUsesCachedDiffStatsWhileRefreshRuns() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let firstDirectoryStats = DiffStats(additions: 12, deletions: 3)
        let secondDirectoryStats = DiffStats(additions: 4, deletions: 1)
        let refreshedFirstDirectoryStats = DiffStats(additions: 14, deletions: 5)
        let secondDirectory = fixtureDirectory("second")
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .zero, .milliseconds(120)],
                diffStatsResults: [
                    .success(firstDirectoryStats),
                    .success(secondDirectoryStats),
                    .success(refreshedFirstDirectoryStats)
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
        await fixture.viewModel.switchToDirectory(
            secondDirectory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForStatsForTesting()

        XCTAssertEqual(fixture.viewModel.diffStats, secondDirectoryStats)

        let statusEntered = expectation(description: "status call entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, firstDirectoryStats)

        await switchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedFirstDirectoryStats)
    }

    func testBaseRefSwitchUsesCachedDiffStatsWhileRefreshRuns() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let mainStats = DiffStats(additions: 8, deletions: 2)
        let releaseStats = DiffStats(additions: 31, deletions: 7)
        let refreshedMainStats = DiffStats(additions: 9, deletions: 3)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .zero, .milliseconds(120)],
                diffStatsResults: [
                    .success(mainStats),
                    .success(releaseStats),
                    .success(refreshedMainStats)
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
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "release",
            remoteName: nil,
            conversationIds: []
        )
        await fixture.diffStore.waitForStatsForTesting()

        XCTAssertEqual(fixture.viewModel.diffStats, releaseStats)

        let statusEntered = expectation(description: "status call entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, mainStats)

        await switchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedMainStats)
    }

    func testRemoteNameSwitchUsesCachedDiffStatsWhileRefreshRuns() async {
        let modifiedFile = FileStatus(path: "feature.swift", originalPath: nil, status: .modified, isStaged: false)
        let originStats = DiffStats(additions: 18, deletions: 2)
        let upstreamStats = DiffStats(additions: 41, deletions: 9)
        let refreshedOriginStats = DiffStats(additions: 21, deletions: 5)
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([modifiedFile]),
                    .success([modifiedFile]),
                    .success([modifiedFile])
                ],
                statusDelays: [.zero, .zero, .milliseconds(120)],
                diffStatsResults: [
                    .success(originStats),
                    .success(upstreamStats),
                    .success(refreshedOriginStats)
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
        await fixture.diffStore.waitForStatsForTesting()
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "upstream",
            conversationIds: []
        )
        await fixture.diffStore.waitForStatsForTesting()

        XCTAssertEqual(fixture.viewModel.diffStats, upstreamStats)

        let statusEntered = expectation(description: "status call entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: "origin",
                conversationIds: []
            )
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertEqual(fixture.viewModel.diffStats, originStats)

        await switchTask.value
        await fixture.diffStore.waitForStatsForTesting()
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedOriginStats)
    }

    private func fixtureDirectory(_ suffix: String) -> String {
        "/tmp/alveary-project-\(suffix)"
    }
}

// swiftlint:enable function_body_length
