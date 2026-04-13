import XCTest

@testable import Alveary

@MainActor
final class ProjectSettingsViewTests: XCTestCase {
    func testRestoreProjectSettingsArchivedThreadClearsArchiveFlag() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )

        try restoreProjectSettingsArchivedThread(thread, modelContext: fixture.context)

        XCTAssertNil(try fixture.requireThread(thread).archivedAt)
    }
}
