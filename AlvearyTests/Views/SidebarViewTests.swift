import XCTest

@testable import Alveary

@MainActor
final class SidebarViewTests: XCTestCase {
    func testArchiveConfirmationMessagePointsToProjectSettingsArchivedThreads() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.archiveConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This archives \"Thread\". You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
        )
    }

    func testDeleteConfirmationMessageQuotesThreadName() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.deleteConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This permanently deletes \"Thread\" and removes its worktree and branch if present."
        )
    }
}
