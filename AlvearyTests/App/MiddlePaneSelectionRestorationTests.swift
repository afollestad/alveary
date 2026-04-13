import XCTest

@testable import Alveary

@MainActor
final class MiddlePaneSelectionRestorationTests: XCTestCase {
    func testResolveSidebarBookmarkReturnsThreadForActiveThreadBookmark() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        let item = resolveSidebarSelectionBookmark(.threadId(thread.persistentModelID), modelContext: fixture.context)

        XCTAssertEqual(item, .thread(thread))
    }

    func testResolveSidebarBookmarkReturnsProjectForArchivedThreadBookmark() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )

        let item = resolveSidebarSelectionBookmark(.threadId(thread.persistentModelID), modelContext: fixture.context)

        XCTAssertEqual(item, .project(try XCTUnwrap(thread.project)))
    }
}
