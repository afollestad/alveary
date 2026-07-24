import SwiftData
import XCTest

@testable import Alveary

// Project-mode deletion coverage re-homed from `ProjectSettingsViewTests` when the
// per-project Archived Threads card was replaced by the Archived screen.
@MainActor
extension ArchivedThreadsViewModelTests {
    /// Project-mode deletion used to live in `ProjectSettingsView`, which never cleared the
    /// launch-restore or commit-message references. The shared sanitize path covers both now.
    func testPermanentDeleteOfProjectModeThreadSanitizesRoutingAndKeepsProject() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Keeper", path: "/tmp/keeper")
        let thread = try insertProjectThread(
            in: fixture,
            name: "Project thread",
            project: project,
            archivedAt: Date()
        )
        let conversationID = try XCTUnwrap(thread.conversations.first?.persistentModelID)
        let (viewModel, appState) = makeViewModel(fixture: fixture)
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        appState.selectedConversationIDs[thread.persistentModelID] = conversationID
        fixture.settingsService.updateRestoreSelection(
            threadID: thread.persistentModelID,
            conversationID: conversationID
        )
        viewModel.refresh()

        await viewModel.confirmPermanentDeletion(try XCTUnwrap(viewModel.items.first))

        XCTAssertNil(fixture.context.resolveThread(id: thread.persistentModelID))
        XCTAssertNotNil(fixture.context.resolveProject(id: project.persistentModelID))
        XCTAssertNil(appState.selectedSidebarItem)
        XCTAssertNil(appState.previousSelection)
        XCTAssertNil(appState.selectedConversationIDs[thread.persistentModelID])
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    /// Re-homed from `ProjectSettingsViewTests`: a project-mode archived thread still gets the
    /// full worktree/provider cleanup now that deletion routes through the Archived screen.
    func testPermanentDeleteOfProjectModeThreadRunsNormalWorktreeAndProviderCleanup() async throws {
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
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()

        await viewModel.confirmPermanentDeletion(try XCTUnwrap(viewModel.items.first))

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
        XCTAssertTrue(viewModel.items.isEmpty)
    }
}
