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
}
