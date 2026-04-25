import XCTest

@testable import Alveary

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

        XCTAssertEqual(fixture.viewModel.files, [modifiedFile])
        XCTAssertEqual(fixture.viewModel.diffStats, .empty)
        XCTAssertNil(fixture.viewModel.gitError)
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
        await fixture.viewModel.switchToDirectory(
            secondDirectory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

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
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "release",
            remoteName: nil,
            conversationIds: []
        )

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
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: "upstream",
            conversationIds: []
        )

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
        XCTAssertEqual(fixture.viewModel.diffStats, refreshedOriginStats)
    }

    private func fixtureDirectory(_ suffix: String) -> String {
        "/tmp/alveary-project-\(suffix)"
    }
}
