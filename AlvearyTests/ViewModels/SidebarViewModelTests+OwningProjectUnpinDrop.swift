import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testCommitSidebarDropUnpinsPinnedThreadOntoOwningProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/unpin-owning")
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 0, project: project)
        fixture.context.insert(thread)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(project.persistentModelID), placement: .into)
        )

        XCTAssertTrue(didCommit)
        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.pinnedSortOrder)
        // Unpinning changes sidebar placement only; the thread still belongs to its project.
        XCTAssertEqual(thread.project?.persistentModelID, project.persistentModelID)
    }

    func testOwningProjectUnpinRejectsAProjectThatDoesNotOwnTheThread() throws {
        let fixture = try SidebarTestFixture()
        let owner = try fixture.insertProject(name: "Owner", path: "/tmp/unpin-owner")
        let other = try fixture.insertProject(name: "Other", path: "/tmp/unpin-other")
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 0, project: owner)
        fixture.context.insert(thread)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(other.persistentModelID), placement: .into)
        )

        XCTAssertFalse(didCommit)
        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(thread.project?.persistentModelID, owner.persistentModelID)
    }

    func testOwningProjectUnpinKeepsAPinnedTaskInItsProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/unpin-task-owning")
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 0, mode: .task, project: project)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(project.persistentModelID), placement: .into)
        )

        // Unlike the Tasks-section unpin, this drop must not detach the Task from its project.
        XCTAssertTrue(didCommit)
        XCTAssertFalse(task.isPinned)
        XCTAssertEqual(task.project?.persistentModelID, project.persistentModelID)
    }

    func testOwningProjectUnpinRejectsUnpinnedAndProjectSources() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/unpin-invalid-sources")
        let thread = AgentThread(name: "Thread", project: project)
        fixture.context.insert(thread)
        try fixture.context.save()
        let target = SidebarDropTarget(
            section: .projects,
            item: .project(project.persistentModelID),
            placement: .into
        )

        for dragItem: SidebarDragItem in [
            .unpinnedTask(thread.persistentModelID),
            .projectThread(thread.persistentModelID),
            .project(project.persistentModelID)
        ] {
            XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(dragItem: dragItem, target: target))
        }
        XCTAssertFalse(thread.isPinned)
    }

    func testOwningProjectUnpinRejectsAModeMismatchedItem() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/unpin-mode-mismatch")
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 0, mode: .task, project: project)
        fixture.context.insert(task)
        try fixture.context.save()

        // Mode mismatch: a pinned Task drags as `.pinnedTask`, never `.pinnedThread`.
        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(project.persistentModelID), placement: .into)
        )

        XCTAssertFalse(didCommit)
        XCTAssertTrue(task.isPinned)
    }

    func testScheduledAttachedPinnedTaskUnpinDropSurfacesTheAttachmentError() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/unpin-scheduled")
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 0, mode: .task, project: project)
        fixture.context.insert(task)
        fixture.context.insert(ScheduledTask(
            title: "Nightly sweep",
            prompt: "Continue in the task.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: task
        ))
        try fixture.context.save()

        // Targeting hides the drop for scheduled-attached threads; `setThreadPinned`'s guard is
        // the backstop when a stale drag lands anyway.
        XCTAssertThrowsError(try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(project.persistentModelID), placement: .into)
        ))
        XCTAssertTrue(task.isPinned)
    }
}
