import SwiftData
import XCTest

@testable import Alveary

// Re-homed from `ProjectSettingsViewTests` when the per-project Archived Threads card was
// replaced by the Archived screen. These exercise `SidebarViewModel.restoreThread` directly,
// which is the shared lifecycle entry point every archived surface routes through.
@MainActor
extension SidebarViewModelTests {
    func testRestoreArchivedProjectThreadRefreshesBadgeCount() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )
        let initial = fixture.notificationManager.refreshBadgeCountCalls

        try await fixture.viewModel.restoreThread(thread)

        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, initial + 1)
    }
}
