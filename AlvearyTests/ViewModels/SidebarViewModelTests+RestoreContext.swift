import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testRestoreThreadRegeneratesPendingRestoreContextPerConversation() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "follow-up"],
            archivedAt: Date()
        )

        let dbThread = try fixture.requireThread(thread)
        let mainConversation = try XCTUnwrap(dbThread.conversations.first(where: { $0.id == "main" }))
        let followUpConversation = try XCTUnwrap(dbThread.conversations.first(where: { $0.id == "follow-up" }))

        mainConversation.events = [
            ConversationEventRecord(
                conversationId: mainConversation.id,
                type: "message",
                role: "user",
                content: "Restore the main conversation context",
                conversation: mainConversation
            )
        ]
        followUpConversation.events = [
            ConversationEventRecord(
                conversationId: followUpConversation.id,
                type: "message",
                role: "assistant",
                content: "Secondary conversation still needs the worktree diff.",
                conversation: followUpConversation
            )
        ]
        try fixture.context.save()

        try fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        let restoredMain = try XCTUnwrap(restoredThread.conversations.first(where: { $0.id == "main" }))
        let restoredFollowUp = try XCTUnwrap(restoredThread.conversations.first(where: { $0.id == "follow-up" }))
        XCTAssertEqual(restoredMain.pendingRestoreContext?.contains("Restore the main conversation context"), true)
        XCTAssertEqual(restoredFollowUp.pendingRestoreContext?.contains("Secondary conversation still needs the worktree diff."), true)
    }
}
