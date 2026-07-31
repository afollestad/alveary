import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testSidebarViewWithPullRequestsHidden() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        sidebar.fixture.settingsService.update { $0.pullRequestsEnabled = false }

        let appState = AppState()
        appState.selectedSidebarItem = .thread(sidebar.activeThread)

        // `Scheduled` now ends the top-level group, so it takes the trailing spacing the
        // `Pull requests` row used to own.
        await assertMacModelSnapshot(modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_pull_requests_hidden"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: appState)
        }
    }
}
