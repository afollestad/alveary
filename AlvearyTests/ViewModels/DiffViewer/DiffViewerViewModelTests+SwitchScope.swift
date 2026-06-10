import Foundation
import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    private static let changedFile = FileStatus(path: "notes.txt", originalPath: nil, status: .modified, isStaged: false)

    func testStatsOnlySwitchLoadsToolbarStatsWithoutContextualAction() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([Self.changedFile])],
                diffStatsResults: [.success(DiffStats(additions: 7, deletions: 2))]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: [],
            scope: .toolbarStatsOnly
        )
        await fixture.diffStore.waitForStatsForTesting()

        XCTAssertEqual(fixture.viewModel.diffStats, DiffStats(additions: 7, deletions: 2))
        XCTAssertEqual(fixture.viewModel.diffStatsLoadState, .loaded)
        // A full-scope switch over these statuses resolves `.commit`; stats-only
        // must skip contextual-action work entirely.
        XCTAssertEqual(fixture.viewModel.contextualAction, .none)
    }

    func testFullSwitchAfterStatsOnlyUpgradesSameTarget() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([Self.changedFile]), .success([Self.changedFile])]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: [],
            scope: .toolbarStatsOnly
        )
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 2)
        XCTAssertEqual(fixture.viewModel.contextualAction, .commit)
    }

    func testStatsOnlySwitchAfterFullSameTargetIsDeduped() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([Self.changedFile])]
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
            baseRef: "main",
            remoteName: nil,
            conversationIds: [],
            scope: .toolbarStatsOnly
        )

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 1)
        XCTAssertEqual(fixture.viewModel.contextualAction, .commit)
    }

    func testRepeatedFullSwitchSameTargetStaysDeduped() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([Self.changedFile])]
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
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 1)
    }
}
