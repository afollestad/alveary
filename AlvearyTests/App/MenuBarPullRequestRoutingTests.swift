import XCTest

@testable import Alveary

@MainActor
final class MenuBarPullRequestRoutingTests: XCTestCase {
    private let summary = makePullRequestSummary(number: 7, title: "Needs eyes", isReviewRequested: true)

    func testOpeningAMenuPullRequestSelectsTheScreenAndOpensItsPane() {
        let appState = AppState()
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())

        openMenuBarPullRequestInAppState(summary, pullRequestsEnabled: true, appState: appState, viewModel: viewModel)

        XCTAssertEqual(appState.selectedSidebarItem, .pullRequests)
        XCTAssertEqual(viewModel.activePaneTarget(for: .screen), .details(summary.id))
    }

    func testShowingAllPullRequestsNeedingReviewLandsOnTheReviewingTab() {
        let appState = AppState()
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())

        showPullRequestsNeedingReviewInAppState(pullRequestsEnabled: true, appState: appState, viewModel: viewModel)

        XCTAssertEqual(appState.selectedSidebarItem, .pullRequests)
        XCTAssertEqual(viewModel.selectedFilter, .reviewing)
    }

    func testRequestsQueuedBeforeTheIntegrationWasTurnedOffGoNowhere() {
        let appState = AppState()
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())

        openMenuBarPullRequestInAppState(summary, pullRequestsEnabled: false, appState: appState, viewModel: viewModel)
        showPullRequestsNeedingReviewInAppState(pullRequestsEnabled: false, appState: appState, viewModel: viewModel)

        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(viewModel.activePaneTarget(for: .screen))
        XCTAssertEqual(viewModel.selectedFilter, .all)
    }
}
