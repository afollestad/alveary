import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testDefaultFileBackedStoresUseTemporaryFixtureRoot() throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachmentRoot = fixture.attachmentStore
            .conversationRootDirectory(conversationId: "test")
            .deletingLastPathComponent()
        let taskWorkspaceService = try XCTUnwrap(
            fixture.taskWorkspaceOwnershipService as? DefaultTaskWorkspaceOwnershipService
        )

        XCTAssertTrue(attachmentRoot.path.hasPrefix(fixture.fileBackedStorageRoot.path))
        XCTAssertTrue(taskWorkspaceService.privateWorkspacesRoot.path.hasPrefix(fixture.fileBackedStorageRoot.path))
        XCTAssertTrue(taskWorkspaceService.worktreeOwnershipRecordsRoot.path.hasPrefix(fixture.fileBackedStorageRoot.path))
        XCTAssertFalse(
            fixture.fileBackedStorageRoot.path.hasPrefix(AppStorageProfile.production.appSupportDirectory.path)
        )
    }
}
