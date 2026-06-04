import XCTest

@testable import Alveary

@MainActor
final class ProjectSettingsViewTests: XCTestCase {
    func testRestoreProjectSettingsArchivedThreadClearsArchiveFlag() async throws {
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

    func testRestoreProjectSettingsArchivedThreadRefreshesBadgeCount() async throws {
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

    func testRestoreProjectSettingsArchivedThreadCallsProviderCompanionAction() async throws {
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

    func testRestoreProjectSettingsArchivedThreadProviderFailureSurfacesUnexpectedErrorWithoutRollingBackLocalRestore() async throws {
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

    func testDeleteProjectSettingsArchivedThreadUsesNormalThreadCleanup() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "side"],
            branch: "alveary/live",
            pendingCleanupBranches: ["alveary/stale", "alveary/live"],
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true,
            archivedAt: Date()
        )
        let appState = AppState()
        let selectedConversationID = try XCTUnwrap(try fixture.requireThread(thread).conversations.first?.persistentModelID)
        let project = try XCTUnwrap(thread.project)
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        appState.selectedConversationIDs[thread.persistentModelID] = selectedConversationID

        try await deleteProjectSettingsArchivedThread(
            thread,
            appState: appState,
            sidebarViewModel: fixture.viewModel
        )

        let destroyCalls = await fixture.agentsManager.destroyCalls()
        let deleteBranchCalls = await fixture.worktreeManager.deleteBranchCalls()
        let removeCalls = await fixture.worktreeManager.removeCalls()

        XCTAssertEqual(destroyCalls.sorted(), ["main", "side"])
        XCTAssertEqual(deleteBranchCalls, [
            .init(projectPath: "/tmp/alveary-project", branch: "alveary/stale")
        ])
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/alveary-worktree", branch: "alveary/live")
        ])
        XCTAssertFalse(try fixture.threadExists(thread))
        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
        XCTAssertNil(appState.selectedConversationIDs[thread.persistentModelID])
    }

    func testDeleteProjectSettingsArchivedThreadPreservesProjectSelection() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date()
        )
        let project = try XCTUnwrap(thread.project)
        let appState = AppState()
        appState.selectedSidebarItem = .project(project)
        appState.previousSelection = .projectPath(project.path)

        try await deleteProjectSettingsArchivedThread(
            thread,
            appState: appState,
            sidebarViewModel: fixture.viewModel
        )

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
    }

    func testDeleteProjectSettingsArchivedThreadKeepsDeletedStateWhenCleanupFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true,
            archivedAt: Date()
        )
        let appState = AppState()
        let selectedConversationID = try XCTUnwrap(try fixture.requireThread(thread).conversations.first?.persistentModelID)
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        appState.selectedConversationIDs[thread.persistentModelID] = selectedConversationID
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await deleteProjectSettingsArchivedThread(
                thread,
                appState: appState,
                sidebarViewModel: fixture.viewModel
            )
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeFailed)
        }

        XCTAssertFalse(try fixture.threadExists(thread))
        XCTAssertNil(appState.selectedConversationIDs[thread.persistentModelID])
        XCTAssertNotEqual(appState.selectedSidebarItem, .thread(thread))
        XCTAssertNotEqual(appState.previousSelection, .threadId(thread.persistentModelID))
    }
}
