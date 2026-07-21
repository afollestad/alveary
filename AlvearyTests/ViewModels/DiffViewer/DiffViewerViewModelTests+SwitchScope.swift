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

    func testProjectAndThreadTargetsInSameWorkspaceDoNotReloadDiffState() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([Self.changedFile])]
            )
        )
        defer { fixture.viewModel.tearDown() }
        let projectTarget = DiffViewerSwitchTarget(
            projectPath: fixture.directory,
            worktreePath: nil,
            directory: fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: ["project-conversation"]
        )
        let threadTarget = DiffViewerSwitchTarget(
            projectPath: fixture.directory,
            worktreePath: nil,
            directory: fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: ["thread-conversation"]
        )

        await fixture.viewModel.switchToTarget(projectTarget)
        await fixture.viewModel.switchToTarget(threadTarget)

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 1)
        XCTAssertEqual(fixture.viewModel.activeDirectory, fixture.directory)
    }

    func testDifferentWorktreesForSameProjectReloadDiffState() async {
        let firstWorktree = "/tmp/alveary-worktree-a"
        let secondWorktree = "/tmp/alveary-worktree-b"
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([Self.changedFile]),
                    .success([Self.changedFile])
                ]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToTarget(DiffViewerSwitchTarget(
            projectPath: fixture.directory,
            worktreePath: firstWorktree,
            directory: firstWorktree,
            baseRef: "main",
            remoteName: nil,
            conversationIds: ["conversation"]
        ))
        await fixture.viewModel.switchToTarget(DiffViewerSwitchTarget(
            projectPath: fixture.directory,
            worktreePath: secondWorktree,
            directory: secondWorktree,
            baseRef: "main",
            remoteName: nil,
            conversationIds: ["conversation"]
        ))

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 2)
        XCTAssertEqual(fixture.viewModel.activeDirectory, secondWorktree)
    }

    func testHiddenAutomaticRefreshSkipsSelectedDiffAndVisibleUpgradeReloadsIt() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([Self.changedFile]),
                    .success([Self.changedFile]),
                    .success([Self.changedFile])
                ],
                diffResults: [
                    Self.modifiedDiff(path: Self.changedFile.path),
                    Self.modifiedDiff(path: Self.changedFile.path)
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
        await fixture.viewModel.selectFile(Self.changedFile, in: fixture.directory)

        await fixture.viewModel.refreshAndInvalidateFileList(
            in: fixture.directory,
            reason: .agentTurnCompleted
        )

        let hiddenDiffCallCount = await fixture.gitService.diffCalls().count
        XCTAssertEqual(hiddenDiffCallCount, 1)

        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let visibleDiffCallCount = await fixture.gitService.diffCalls().count
        XCTAssertEqual(visibleDiffCallCount, 2)
    }

    func testRevealDuringHiddenRefreshStillQueuesFullUpgrade() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [
                    .success([Self.changedFile]),
                    .success([Self.changedFile]),
                    .success([Self.changedFile])
                ],
                statusDelays: [.zero, .milliseconds(150), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        fixture.viewModel.setWatchingEnabled(false)

        let hiddenStatusEntered = expectation(description: "hidden status refresh entered")
        await fixture.gitService.setOnStatus { hiddenStatusEntered.fulfill() }
        let hiddenRefresh = Task {
            await fixture.viewModel.refresh(
                in: fixture.directory,
                reason: .agentTurnCompleted,
                scope: .toolbarStatsOnly
            )
        }

        await fulfillment(of: [hiddenStatusEntered], timeout: 2.0)
        await fixture.gitService.setOnStatus(nil)
        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await hiddenRefresh.value

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 3)
        XCTAssertEqual(fixture.viewModel.contextualAction, .commit)
    }

    func testNewerHiddenRefreshSurvivesOlderFullRefreshCompletionUntilReveal() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: Array(repeating: .success([Self.changedFile]), count: 4),
                statusDelays: [.zero, .milliseconds(150), .milliseconds(150), .zero]
            )
        )
        defer { fixture.viewModel.tearDown() }

        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )

        let fullStatusEntered = expectation(description: "visible full status refresh entered")
        await fixture.gitService.setOnStatus { fullStatusEntered.fulfill() }
        let olderFullRefresh = Task {
            await fixture.viewModel.refresh(in: fixture.directory, reason: .manual)
        }
        await fulfillment(of: [fullStatusEntered], timeout: 2.0)

        let hiddenStatusEntered = expectation(description: "newer hidden status refresh entered")
        await fixture.gitService.setOnStatus { hiddenStatusEntered.fulfill() }
        fixture.viewModel.setWatchingEnabled(false)
        let newerHiddenRefresh = Task {
            await fixture.viewModel.refresh(
                in: fixture.directory,
                reason: .agentTurnCompleted,
                scope: .toolbarStatsOnly
            )
        }
        await fulfillment(of: [hiddenStatusEntered], timeout: 2.0)

        await fixture.gitService.setOnStatus(nil)
        fixture.viewModel.setWatchingEnabled(true)
        await fixture.viewModel.switchToDirectory(
            fixture.directory,
            baseRef: "main",
            remoteName: nil,
            conversationIds: []
        )
        await olderFullRefresh.value
        await newerHiddenRefresh.value

        let statusCalls = await fixture.gitService.statusCallCount()
        XCTAssertEqual(statusCalls, 4)
        XCTAssertEqual(fixture.viewModel.contextualAction, .commit)
    }
}
