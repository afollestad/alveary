import XCTest

@testable import Alveary

@MainActor
final class ProjectSettingsViewTests: XCTestCase {
    func testArchivedProjectThreadsExcludeLinkedScheduledRunWithFallbackMode() throws {
        let fixture = try SidebarTestFixture()
        let projectThread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            archivedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let project = try XCTUnwrap(projectThread.project)
        let (linkedTask, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "project-settings-fallback-task"
        )
        linkedTask.modeRawValue = "future-mode"
        linkedTask.project = project
        linkedTask.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        try fixture.context.save()

        let archivedThreads = archivedProjectThreads(projectPath: project.path, modelContext: fixture.context)

        XCTAssertEqual(archivedThreads.map(\.persistentModelID), [projectThread.persistentModelID])
    }

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
            archivedAt: Date(),
            provider: "codex",
            providerSessionId: "codex-thread",
            providerSessionProviderId: "codex",
            providerSessionWorkingDirectory: "/tmp/alveary-worktree"
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
        XCTAssertTrue(deleteBranchCalls.isEmpty)
        XCTAssertEqual(removeCalls, [
            .init(projectPath: "/tmp/alveary-project", worktreePath: "/tmp/alveary-worktree", branch: "alveary/live")
        ])
        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions.count, 2)
        guard case .resolve(let resolveSnapshot) = actions.first,
              case .delete(let deleteSnapshot) = actions.last else {
            XCTFail("Expected resolve then delete actions")
            return
        }
        XCTAssertEqual(Set(resolveSnapshot.conversationIDs), ["main", "side"])
        XCTAssertEqual(deleteSnapshot, resolveSnapshot)
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

    func testArchivedThreadDeleteFailureDoesNotRestoreSelectionUnderVoiceModelModal() async throws {
        let fixture = try SidebarTestFixture(saveDeletionCommit: { _ in
            throw ProjectVoiceNavigationTestError.persistenceFailed
        })
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date()
        )
        let project = try XCTUnwrap(thread.project)
        let conversationID = try XCTUnwrap(try fixture.requireThread(thread).conversations.first?.persistentModelID)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        appState.selectedConversationIDs[thread.persistentModelID] = conversationID
        let voiceInputService = DisabledVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: voiceInputService)
        let modalSink = ProjectSettingsVoiceModelModalSink()
        lifecycleController.setActiveComposerSink(modalSink)

        do {
            try await deleteProjectSettingsArchivedThread(
                thread,
                appState: appState,
                sidebarViewModel: fixture.viewModel,
                voiceInputLifecycleController: lifecycleController
            )
            XCTFail("Expected delete to throw")
        } catch ProjectVoiceNavigationTestError.persistenceFailed {
            // Expected pre-commit failure.
        }

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
        XCTAssertNil(appState.selectedConversationIDs[thread.persistentModelID])
        XCTAssertTrue(try fixture.threadExists(thread))
    }
}

private final class ProjectSettingsVoiceModelModalSink: VoiceInputComposerSink {
    var isModelPreparationModalPresented: Bool { true }

    func forceVoiceInputCommitSynchronously() {}
}

private enum ProjectVoiceNavigationTestError: Error {
    case persistenceFailed
}
