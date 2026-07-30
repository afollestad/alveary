import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testTopLevelRowItemsDropHiddenConditionalRows() {
        let allVisible: [SidebarItem] = [.skills, .mcp, .scheduled, .pullRequests, .archived]
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: true, hasArchivedThreads: true),
            allVisible
        )

        let withoutPullRequests: [SidebarItem] = [.skills, .mcp, .scheduled, .archived]
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: false, hasArchivedThreads: true),
            withoutPullRequests
        )

        let onlyFixedRows: [SidebarItem] = [.skills, .mcp, .scheduled]
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: false, hasArchivedThreads: false),
            onlyFixedRows
        )
    }

    /// The last element owns both the group's trailing spacing and the `.topLevelTerminal` drag
    /// role that the empty-`Pinned` drop target aims at, so it must resolve in every combination.
    func testTopLevelTerminalRowFollowsTheConditionalRowsVisibility() {
        // Pull Requests ends the group while Archived is hidden, and yields it once Archived appears.
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: true, hasArchivedThreads: false).last,
            .pullRequests
        )
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: true, hasArchivedThreads: true).last,
            .archived
        )
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: false, hasArchivedThreads: true).last,
            .archived
        )
        // Both conditional rows hidden, so the role falls back to Scheduled rather than vanishing.
        XCTAssertEqual(
            sidebarTopLevelRowItems(showsPullRequests: false, hasArchivedThreads: false).last,
            .scheduled
        )
    }

    func testHidingPullRequestsClearsSelectionAndBookmark() throws {
        let fixture = try SidebarTestFixture()
        let appState = AppState()
        appState.selectedSidebarItem = .pullRequests
        appState.previousSelection = .pullRequests

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        view.handlePullRequestsVisibilityChange(showsPullRequests: false)

        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
    }

    func testShowingPullRequestsLeavesSelectionAlone() throws {
        let fixture = try SidebarTestFixture()
        let appState = AppState()
        appState.selectedSidebarItem = .pullRequests
        appState.previousSelection = .pullRequests

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        view.handlePullRequestsVisibilityChange(showsPullRequests: true)

        XCTAssertEqual(appState.selectedSidebarItem, .pullRequests)
        XCTAssertEqual(appState.previousSelection, .pullRequests)
    }

    func testHidingPullRequestsPreservesAnUnrelatedSelection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-hide-pull-requests")
        let appState = AppState()
        appState.selectedSidebarItem = .project(project)
        appState.previousSelection = .scheduled

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        view.handlePullRequestsVisibilityChange(showsPullRequests: false)

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .scheduled)
    }
}
