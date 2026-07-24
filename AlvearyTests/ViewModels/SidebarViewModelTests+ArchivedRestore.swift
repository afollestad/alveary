import SwiftData
import XCTest

@testable import Alveary

// Re-homed from `ProjectSettingsViewTests` when the per-project Archived Threads card was
// replaced by the Archived screen. These exercise `SidebarViewModel.restoreThread` directly,
// which is the shared lifecycle entry point every archived surface routes through.
@MainActor
extension SidebarViewModelTests {
    func testRestoreArchivedProjectThreadRegeneratesPendingRestoreContext() async throws {
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

        try await fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        let pendingRestoreContext = restoredThread.conversations.first?.pendingRestoreContext
        XCTAssertEqual(pendingRestoreContext?.contains("Reconnect me to the earlier diff discussion"), true)
        XCTAssertEqual(pendingRestoreContext?.contains("Restoring context from local history."), true)
    }

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

    func testRestoreArchivedProjectThreadCallsProviderCompanionAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            provider: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            )),
            .unarchive(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            ))
        ])
    }

    func testRestoreArchivedProjectThreadProviderFailureSurfacesToastWithoutRollingBackLocalRestore() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .unarchive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(unarchiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            provider: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }
}
