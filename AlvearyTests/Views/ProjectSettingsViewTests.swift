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

        let dbThread = try fixture.requireThread(thread)
        guard let conversation = dbThread.conversations.first else {
            XCTFail("Expected a conversation")
            return
        }
        conversation.events = [
            ConversationEventRecord(
                conversationId: conversation.id,
                type: "message",
                role: "user",
                content: "Reconnect me to the earlier diff discussion",
                conversation: conversation
            ),
            ConversationEventRecord(
                conversationId: conversation.id,
                type: "message",
                role: "assistant",
                content: "The branch already has the diff staged locally.",
                conversation: conversation
            )
        ]
        try fixture.context.save()

        try restoreProjectSettingsArchivedThread(
            thread,
            modelContext: fixture.context,
            notificationManager: fixture.notificationManager
        )

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        let pendingRestoreContext = restoredThread.conversations.first?.pendingRestoreContext
        XCTAssertEqual(pendingRestoreContext?.contains("Reconnect me to the earlier diff discussion"), true)
        XCTAssertEqual(pendingRestoreContext?.contains("Fresh session restore context"), true)
    }

    func testRestoreProjectSettingsArchivedThreadRefreshesBadgeCount() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date()
        )
        let initial = fixture.notificationManager.refreshBadgeCountCalls

        try restoreProjectSettingsArchivedThread(
            thread,
            modelContext: fixture.context,
            notificationManager: fixture.notificationManager
        )

        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, initial + 1)
    }
}
