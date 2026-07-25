import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testCommitSidebarDropPinsUnpinnedTaskBeforePinnedAnchor() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/pinned-anchor", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let pinnedTask = AgentThread(name: "Pinned Task", isPinned: true, pinnedSortOrder: 1, mode: .task)
        let task = AgentThread(name: "Task", mode: .task)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(pinnedTask)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .pinnedTask(pinnedTask.persistentModelID), placement: .before)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 0)
        XCTAssertEqual(task.pinnedSortOrder, 1)
        XCTAssertEqual(pinnedTask.pinnedSortOrder, 2)
    }

    func testCommitSidebarDropPinsUnpinnedTaskAtSectionEnd() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/pinned-end", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let task = AgentThread(name: "Task", mode: .task)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 0)
        XCTAssertEqual(task.pinnedSortOrder, 1)
    }

    func testCommitSidebarDropPinsFirstTaskIntoEmptyPinnedSection() throws {
        let fixture = try SidebarTestFixture()
        let task = AgentThread(name: "Task", mode: .task)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 0)
    }

    func testUnpinnedTaskDropRejectsProjectsSection() throws {
        let fixture = try SidebarTestFixture()
        let task = AgentThread(name: "Task", mode: .task)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(task.isPinned)
        XCTAssertNil(task.pinnedSortOrder)
    }

    func testCommitSidebarDropUnpinsPinnedTaskIntoTasksSection() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/unpin-anchor", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 1, mode: .task)
        let trailingTask = AgentThread(name: "Trailing", isPinned: true, pinnedSortOrder: 2, mode: .task)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(task)
        fixture.context.insert(trailingTask)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertFalse(task.isPinned)
        XCTAssertNil(task.pinnedSortOrder)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 0)
        XCTAssertEqual(trailingTask.pinnedSortOrder, 1)
    }

    func testTasksSectionDropRejectsNonPinnedTaskSources() throws {
        let fixture = try SidebarTestFixture()
        let owner = Project(path: "/tmp/tasks-drop-owner", name: "Owner", sidebarSortOrder: 0)
        let pinnedProjectThread = AgentThread(
            name: "Pinned Thread",
            isPinned: true,
            pinnedSortOrder: 0,
            project: owner
        )
        owner.threads = [pinnedProjectThread]
        let unpinnedTask = AgentThread(name: "Unpinned", mode: .task)
        fixture.context.insert(owner)
        fixture.context.insert(unpinnedTask)
        try fixture.context.save()

        for dragItem in [
            SidebarDragItem.pinnedThread(pinnedProjectThread.persistentModelID),
            .unpinnedTask(unpinnedTask.persistentModelID),
            .project(owner.persistentModelID)
        ] {
            XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
                dragItem: dragItem,
                target: SidebarDropTarget(section: .tasks, placement: .end)
            ))
        }
        XCTAssertTrue(pinnedProjectThread.isPinned)
        XCTAssertFalse(unpinnedTask.isPinned)
        XCTAssertFalse(owner.isPinned)
    }

    func testTasksSectionDropRejectsScheduledAttachedPinnedTask() throws {
        let fixture = try SidebarTestFixture()
        let task = AgentThread(name: "Attached", isPinned: true, pinnedSortOrder: 0, mode: .task)
        let definition = ScheduledTask(
            title: "Attached schedule",
            prompt: "Continue in the pinned task.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: task
        )
        fixture.context.insert(task)
        fixture.context.insert(definition)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        ))
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 0)
    }

    func testUnpinnedTaskDropRejectsStaleSources() throws {
        let fixture = try SidebarTestFixture()
        let archived = AgentThread(name: "Archived", archivedAt: Date(), mode: .task)
        let draft = AgentThread(name: "Draft", isDraft: true, mode: .task)
        let pinned = AgentThread(name: "Pinned", isPinned: true, pinnedSortOrder: 0, mode: .task)
        let projectMode = AgentThread(name: "Project Mode")
        let deleted = AgentThread(name: "Deleted", mode: .task)
        for thread in [archived, draft, pinned, projectMode, deleted] {
            fixture.context.insert(thread)
        }
        try fixture.context.save()
        let deletedID = deleted.persistentModelID
        fixture.context.delete(deleted)
        try fixture.context.save()

        for dragItem in [
            SidebarDragItem.unpinnedTask(deletedID),
            .unpinnedTask(archived.persistentModelID),
            .unpinnedTask(draft.persistentModelID),
            .unpinnedTask(pinned.persistentModelID),
            .unpinnedTask(projectMode.persistentModelID)
        ] {
            XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
                dragItem: dragItem,
                target: SidebarDropTarget(section: .pinned, placement: .end)
            ))
        }
        XCTAssertFalse(archived.isPinned)
        XCTAssertFalse(draft.isPinned)
        XCTAssertEqual(pinned.pinnedSortOrder, 0)
        XCTAssertFalse(projectMode.isPinned)
    }
}
