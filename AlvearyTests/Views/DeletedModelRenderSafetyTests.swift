import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// Guards the render paths that a thread or project delete can pull out from under.
///
/// A SwiftUI `body` still holding a `@Model` after its row is deleted can trap inside SwiftData's
/// persisted-property read with `_assertionFailure`, killing the process. Deleting several sidebar
/// rows in a row is what produced that report: the row re-renders from its own `@State` — hover,
/// and the cleanup pill's collapse task — while `List` is still animating it out.
///
/// **These are contract tests, not reproductions.** A fresh test container keeps a deleted row's
/// backing data materialized, so reading one here does not trap (verified against in-memory and
/// on-disk stores, cross-context deletes, and a post-save `rollback()`). What they lock in is the
/// structural property that makes the trap unreachable: the render path holds values, or resolves
/// its token first and treats a gone row as absent. Reintroducing a stored `@Model` or an
/// unresolved token read fails these at compile time or on the fallback assertions.
@MainActor
final class DeletedModelRenderSafetyTests: XCTestCase {
    // MARK: - Sidebar rows

    func testThreadRowPresentationStillReadsAfterItsThreadIsDeleted() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-row-presentation",
            worktreePath: "/tmp/alveary-worktree",
            useWorktree: true
        )
        let presentation = SidebarThreadRowPresentation(thread: thread)
        let expectedWorktreePath = thread.worktreePath

        fixture.context.delete(thread)
        try fixture.context.save()

        XCTAssertEqual(presentation.displayName, "Thread")
        XCTAssertTrue(presentation.showsWorktreeIndicator)
        XCTAssertFalse(presentation.showsScheduledIndicator)
        // The tooltip derives from the stored value alone, so it stays readable after the delete.
        XCTAssertEqual(presentation.worktreePath, expectedWorktreePath)
        XCTAssertNotEqual(
            sidebarThreadWorktreeTooltipText(worktreePath: presentation.worktreePath),
            "Worktree path not created yet"
        )
        XCTAssertFalse(presentation.isPinned)
    }

    /// The reported crash, end to end: the row's presentation is built while the row is live, the
    /// hover-pill delete commits, and the still-mounted row re-reads its title.
    func testThreadRowPresentationStillReadsAfterConfirmDeleteThread() async throws {
        let fixture = try SidebarTestFixture()
        let alpha = Self.makeTaskThread(name: "Alpha")
        let beta = Self.makeTaskThread(name: "Beta")
        fixture.context.insert(alpha)
        fixture.context.insert(beta)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(alpha)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        let presentation = SidebarThreadRowPresentation(thread: alpha)

        await view.confirmDeleteThread(alpha)

        XCTAssertFalse(try fixture.threadExists(alpha))
        XCTAssertEqual(presentation.displayName, "Alpha")
        XCTAssertEqual(presentation.threadID, alpha.persistentModelID)
        XCTAssertTrue(try fixture.threadExists(beta))
    }

    // MARK: - Selection tokens

    func testMainPaneHeaderFallsBackWhenTheSelectedThreadIsDeleted() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-header",
            hasCompletedInitialSetup: true
        )
        let live = MainPaneHeaderPresentation(selection: .thread(thread), modelContext: fixture.context)
        XCTAssertEqual(live.title, .markdown("Thread"))
        XCTAssertTrue(live.showsNewConversationButton)

        fixture.context.delete(thread)
        try fixture.context.save()

        let stale = MainPaneHeaderPresentation(selection: .thread(thread), modelContext: fixture.context)
        XCTAssertEqual(stale.title, .plain("Alveary"))
        XCTAssertFalse(stale.showsNewConversationButton)
    }

    func testSidebarItemEqualityAndHashingSurviveProjectDeletion() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-hashing")
        let other = try fixture.insertProject(name: "Other", path: "/tmp/alveary-hashing-other")

        fixture.context.delete(project)
        try fixture.context.save()

        // `Hashable` runs on SwiftUI's schedule, including on a selection whose row is gone.
        XCTAssertEqual(SidebarItem.project(project), SidebarItem.project(project))
        XCTAssertNotEqual(SidebarItem.project(project), SidebarItem.project(other))
        XCTAssertEqual(
            Set([SidebarItem.project(project), SidebarItem.project(other)]).count,
            2
        )
    }

    func testResolvedSelectionIsNilForADeletedThreadAndPassthroughForStaticRows() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-resolve")

        XCTAssertNotNil(SidebarItem.thread(thread).resolved(in: fixture.context))
        XCTAssertEqual(SidebarItem.archived.resolved(in: fixture.context), .archived)

        fixture.context.delete(thread)
        try fixture.context.save()

        XCTAssertNil(SidebarItem.thread(thread).resolved(in: fixture.context))
    }

    // MARK: - Thread detail

    func testThreadDetailRenderGatesCloseWhenItsThreadIsDeleted() throws {
        let fixture = try ThreadDetailProjectTrustFixture(hasCompletedInitialSetup: true)
        XCTAssertTrue(fixture.view.canCreateConversationFromEmptyState)

        fixture.context.delete(fixture.thread)
        try fixture.context.save()

        XCTAssertNil(fixture.view.liveThread)
        XCTAssertFalse(fixture.view.canCreateConversationFromEmptyState)
        XCTAssertFalse(fixture.view.canPersistEmptyConversationSelection)
        XCTAssertFalse(fixture.view.shouldShowConversationStrip(conversationCount: 2))
    }

    private static func makeTaskThread(name: String) -> AgentThread {
        let thread = AgentThread(
            name: name,
            hasCustomName: true,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/\(UUID().uuidString)",
                ownershipStrategy: .projectLocal
            )
        )
        thread.conversations = [
            Conversation(
                id: "\(name.lowercased())-main",
                title: name,
                provider: "claude",
                isMain: true,
                displayOrder: 0,
                thread: thread
            )
        ]
        return thread
    }
}
