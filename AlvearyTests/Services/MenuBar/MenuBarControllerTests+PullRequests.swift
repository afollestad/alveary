import AppKit
import Foundation
import XCTest

@testable import Alveary

extension MenuBarControllerTests {
    func testMenuListsPullRequestsNeedingReviewAboveRecentThreads() async throws {
        let fixture = try MenuBarControllerTestFixture()
        let alpha = makeReviewRequest(number: 1, title: "Alpha")
        let beta = makeReviewRequest(number: 2, title: "Beta", repo: "octo/beta")
        fixture.pullRequestsService.listResult = .success(PullRequestListResult(summaries: [alpha, beta], warnings: []))
        let controller = fixture.makeController()
        controller.start()
        try await waitForReviewRequests(fixture, phase: .loaded)
        let menu = NSMenu()

        controller.rebuild(menu)

        XCTAssertEqual(
            Array(menu.items.prefix(6).map(\.title)),
            ["Needs review", "Alpha", "Beta", "", "Recent threads", "No Recent Threads"]
        )
        XCTAssertTrue(menu.items[0].isSectionHeader)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertTrue(menu.items[4].isSectionHeader)
        XCTAssertEqual(menu.items[1].subtitle, "octo/alpha#1")
        XCTAssertEqual(menu.items[2].subtitle, "octo/beta#2")
        controller.stop()
    }

    func testPullRequestSectionSaysWhyItHasNoRows() async throws {
        let fixture = try MenuBarControllerTestFixture()
        let gate = PullRequestsServiceGate()
        fixture.pullRequestsService.listGate = gate
        fixture.pullRequestsService.listResult = .failure(.notAuthenticated)
        let controller = fixture.makeController()
        controller.start()
        let menu = NSMenu()

        controller.rebuild(menu)
        XCTAssertEqual(menu.items[1].title, "Loading…")
        XCTAssertNil(menu.items[1].action)

        gate.open()
        try await waitForReviewRequests(fixture, phase: .failed)
        controller.rebuild(menu)
        XCTAssertEqual(menu.items[1].title, "Couldn't Load Pull Requests")
        XCTAssertNil(menu.items[1].action)

        fixture.pullRequestsService.listResult = .success(PullRequestListResult(summaries: [], warnings: []))
        controller.refreshAfterWake()
        try await waitForReviewRequests(fixture, phase: .loaded)
        controller.rebuild(menu)
        XCTAssertEqual(menu.items[1].title, "No Pull Requests")
        XCTAssertNil(menu.items[1].action)
        controller.stop()
    }

    func testPullRequestSectionNeedsTheSettingTheIconAndTheIntegration() throws {
        var listingOff = AppSettings()
        listingOff.menuBarShowsPullRequestsNeedingReview = false
        var integrationOff = AppSettings()
        integrationOff.pullRequestsEnabled = false
        var iconOff = AppSettings()
        iconOff.showsMenuBarIcon = false

        for settings in [listingOff, integrationOff, iconOff] {
            let fixture = try MenuBarControllerTestFixture(settings: settings)
            let controller = fixture.makeController()
            controller.start()
            let menu = NSMenu()

            controller.rebuild(menu)

            XCTAssertEqual(fixture.reviewRequestsMonitor.phase, .inactive)
            XCTAssertEqual(menu.items.first?.title, "Recent threads")
            XCTAssertEqual(fixture.pullRequestsService.listCallCount, 0)
            controller.stop()
        }
    }

    func testLongReviewQueuesCollapseIntoAMoreItem() async throws {
        let fixture = try MenuBarControllerTestFixture()
        let rows = (1...12).map { makeReviewRequest(number: $0, title: "PR \($0)") }
        fixture.pullRequestsService.listResult = .success(PullRequestListResult(summaries: rows, warnings: []))
        let controller = fixture.makeController()
        controller.start()
        try await waitForReviewRequests(fixture, phase: .loaded)
        var reopenCount = 0
        fixture.mainWindowPresenter.register { reopenCount += 1 }
        let menu = NSMenu()

        controller.rebuild(menu)

        let listed = menu.items.filter { $0.representedObject is PullRequestSummary }
        XCTAssertEqual(listed.count, MenuBarController.maxListedPullRequests)
        try performMenuItem(titled: "2 More…", in: menu)
        XCTAssertEqual(reopenCount, 1)
        XCTAssertEqual(fixture.commandRouter.pendingCommand?.kind, .showPullRequestsNeedingReview)
        controller.stop()
    }

    func testPickingAPullRequestRevealsTheWindowThenRoutesIt() async throws {
        let fixture = try MenuBarControllerTestFixture()
        let alpha = makeReviewRequest(number: 1, title: "Alpha")
        fixture.pullRequestsService.listResult = .success(PullRequestListResult(summaries: [alpha], warnings: []))
        let controller = fixture.makeController()
        controller.start()
        try await waitForReviewRequests(fixture, phase: .loaded)
        var reopenCount = 0
        fixture.mainWindowPresenter.register {
            XCTAssertNil(fixture.commandRouter.pendingCommand, "Reopen before routing into the new window")
            reopenCount += 1
        }
        let menu = NSMenu()
        controller.rebuild(menu)

        try performMenuItem(titled: "Alpha", in: menu)

        XCTAssertEqual(reopenCount, 1)
        XCTAssertEqual(fixture.commandRouter.pendingCommand?.kind, .openPullRequest(alpha))
        controller.stop()
    }

    func testIconIsBadgedOnlyWhilePullRequestsWait() async throws {
        let fixture = try MenuBarControllerTestFixture()
        let alpha = makeReviewRequest(number: 1, title: "Alpha")
        let beta = makeReviewRequest(number: 2, title: "Beta")
        fixture.pullRequestsService.listResult = .success(PullRequestListResult(summaries: [alpha, beta], warnings: []))
        let controller = fixture.makeController()
        controller.start()
        XCTAssertEqual(controller.statusButtonPresentation, .init(isBadged: false, label: "Alveary"))

        try await waitForReviewRequests(fixture, phase: .loaded)
        XCTAssertEqual(
            controller.statusButtonPresentation,
            .init(isBadged: true, label: "Alveary — 2 pull requests need review")
        )

        fixture.settingsService.update { $0.menuBarShowsPullRequestsNeedingReview = false }
        controller.applySettings()
        XCTAssertEqual(controller.statusButtonPresentation, .init(isBadged: false, label: "Alveary"))
        controller.stop()
    }

    func testBadgedIconIsADistinctTemplateImage() throws {
        let plain = try XCTUnwrap(MenuBarStatusIcon.image(badged: false))
        let badged = try XCTUnwrap(MenuBarStatusIcon.image(badged: true))

        XCTAssertFalse(plain === badged)
        XCTAssertTrue(plain.isTemplate)
        XCTAssertTrue(badged.isTemplate)
        XCTAssertEqual(badged.size, plain.size)
    }

    private func makeReviewRequest(number: Int, title: String, repo: String = "octo/alpha") -> PullRequestSummary {
        makePullRequestSummary(
            number: number,
            repo: repo,
            title: title,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - number)),
            isReviewRequested: true
        )
    }

    private func waitForReviewRequests(
        _ fixture: MenuBarControllerTestFixture,
        phase: MenuBarReviewRequestsMonitor.Phase
    ) async throws {
        try await scheduledTaskLifecycleWaitUntil("the review monitor reaches \(phase)") {
            fixture.reviewRequestsMonitor.phase == phase
        }
    }

    private func performMenuItem(titled title: String, in menu: NSMenu) throws {
        let index = try XCTUnwrap(menu.items.firstIndex { $0.title == title })
        menu.performActionForItem(at: index)
    }
}
