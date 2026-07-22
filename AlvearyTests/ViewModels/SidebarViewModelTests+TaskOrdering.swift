import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testActiveTaskThreadsSortsNewestUnpinnedTasksAndExcludesOtherModesAndStates() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/task-ordering-project", name: "Project")
        let newest = AgentThread(name: "Newest", modifiedAt: Date(timeIntervalSince1970: 300), mode: .task)
        let oldest = AgentThread(name: "Oldest", modifiedAt: Date(timeIntervalSince1970: 100), mode: .task)
        let pinned = AgentThread(
            name: "Pinned",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 400),
            mode: .task
        )
        let draft = AgentThread(
            name: "Draft",
            isDraft: true,
            modifiedAt: Date(timeIntervalSince1970: 500),
            mode: .task
        )
        let archived = AgentThread(
            name: "Archived",
            modifiedAt: Date(timeIntervalSince1970: 600),
            archivedAt: Date(),
            mode: .task
        )
        let projectThread = AgentThread(
            name: "Project thread",
            modifiedAt: Date(timeIntervalSince1970: 700),
            project: project
        )
        project.threads = [projectThread]
        fixture.context.insert(project)
        for task in [newest, oldest, pinned, draft, archived] {
            fixture.context.insert(task)
        }
        try fixture.context.save()

        XCTAssertEqual(fixture.viewModel.activeTaskThreads().map(\.persistentModelID), [
            newest.persistentModelID,
            oldest.persistentModelID
        ])
        XCTAssertTrue(fixture.viewModel.hasAnyActiveTaskThreads())
    }

    func testTaskEmptyStateCountIncludesPinnedTasks() throws {
        let fixture = try SidebarTestFixture()
        let pinned = AgentThread(name: "Pinned", isPinned: true, mode: .task)
        let archived = AgentThread(name: "Archived", archivedAt: Date(), mode: .task)
        fixture.context.insert(pinned)
        fixture.context.insert(archived)
        try fixture.context.save()

        XCTAssertTrue(fixture.viewModel.activeTaskThreads().isEmpty)
        XCTAssertTrue(fixture.viewModel.hasAnyActiveTaskThreads())
    }

    func testTaskEmptyStateCountExcludesArchivedAndDraftTasks() throws {
        let fixture = try SidebarTestFixture()
        let draft = AgentThread(name: "Draft", isDraft: true, mode: .task)
        let archived = AgentThread(name: "Archived", archivedAt: Date(), mode: .task)
        fixture.context.insert(draft)
        fixture.context.insert(archived)
        try fixture.context.save()

        XCTAssertTrue(fixture.viewModel.activeTaskThreads().isEmpty)
        XCTAssertFalse(fixture.viewModel.hasAnyActiveTaskThreads())
    }

    func testScheduledProjectRunsAndUnknownProjectSnapshotsStayOutOfTasks() throws {
        let fixture = try SidebarTestFixture()
        let (projectModeTask, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "project-mode-active-task"
        )
        let (unknownModeTask, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "unknown-mode-active-task"
        )
        projectModeTask.modeRawValue = AgentThreadMode.project.rawValue
        projectModeTask.modifiedAt = Date(timeIntervalSinceReferenceDate: 200)
        unknownModeTask.modeRawValue = "future-mode"
        unknownModeTask.modifiedAt = Date(timeIntervalSinceReferenceDate: 100)
        try fixture.context.save()

        let activeTasks = fixture.viewModel.activeTaskThreads()

        XCTAssertTrue(activeTasks.isEmpty)
        XCTAssertEqual(unknownModeTask.effectiveMode, .project)
        XCTAssertFalse(fixture.viewModel.hasAnyActiveTaskThreads())
        XCTAssertTrue(shouldShowNoTasksPlaceholder(
            activeTaskThreads: activeTasks,
            hasAnyActiveTaskThreads: fixture.viewModel.hasAnyActiveTaskThreads()
        ))
    }

    func testPinnedItemsIncludeTasksEvenWhenTheirBackingProjectIsPinned() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(
            path: "/tmp/pinned-task-project",
            name: "Pinned Project",
            isPinned: true,
            pinnedSortOrder: 0
        )
        let hiddenProjectThread = AgentThread(
            name: "Project Child",
            isPinned: true,
            pinnedSortOrder: 1,
            project: project
        )
        let task = AgentThread(
            name: "Task",
            isPinned: true,
            pinnedSortOrder: 1,
            mode: .task,
            project: project
        )
        project.threads = [hiddenProjectThread, task]
        fixture.context.insert(project)
        try fixture.context.save()

        let pinnedItems = fixture.viewModel.pinnedItems(projects: [project])

        XCTAssertEqual(pinnedItems.map(\.sidebarItem), [.project(project), .thread(task)])
        XCTAssertEqual(pinnedItems.map(\.dragItem), [
            .project(project.persistentModelID),
            .pinnedTask(task.persistentModelID)
        ])
        XCTAssertEqual(fixture.viewModel.pinnedThreads().map(\.persistentModelID), [task.persistentModelID])
    }

    func testSetProjectPinnedDoesNotClearPinnedTaskBackedByProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/task-backed-project", name: "Project")
        let projectThread = AgentThread(
            name: "Project Thread",
            isPinned: true,
            pinnedSortOrder: 0,
            project: project
        )
        let task = AgentThread(
            name: "Task",
            isPinned: true,
            pinnedSortOrder: 1,
            mode: .task,
            project: project
        )
        project.threads = [projectThread, task]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setProjectPinned(project, isPinned: true)

        XCTAssertFalse(projectThread.isPinned)
        XCTAssertNil(projectThread.pinnedSortOrder)
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 0)
        XCTAssertTrue(project.isPinned)
        XCTAssertEqual(project.pinnedSortOrder, 1)
    }

    func testSetThreadPinnedAllowsTaskBackedByPinnedProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(
            path: "/tmp/pinned-task-owner",
            name: "Pinned Project",
            isPinned: true,
            pinnedSortOrder: 0
        )
        let task = AgentThread(name: "Task", mode: .task, project: project)
        project.threads = [task]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setThreadPinned(task, isPinned: true)

        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 1)
        XCTAssertEqual(
            fixture.viewModel.pinnedItems(projects: [project]).map(\.dragItem),
            [.project(project.persistentModelID), .pinnedTask(task.persistentModelID)]
        )
    }

    func testLinkedScheduledRunWithUnknownProjectModeUsesProjectDomain() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(
            path: "/tmp/pinned-fallback-task-owner",
            name: "Pinned Project",
            isPinned: true,
            pinnedSortOrder: 0
        )
        fixture.context.insert(project)
        let (task, _) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "unknown-mode-pinned-task"
        )
        task.modeRawValue = "future-mode"
        task.project = project
        try fixture.context.save()

        try fixture.viewModel.setThreadPinned(task, isPinned: true)

        XCTAssertEqual(task.effectiveMode, .project)
        XCTAssertFalse(task.isPinned)
        XCTAssertEqual(
            fixture.viewModel.pinnedItems(projects: [project]).map(\.dragItem),
            [.project(project.persistentModelID)]
        )
        XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, placement: .end)
        ))
    }

    func testCommitSidebarDropReordersPinnedTaskWithinMixedPinnedItems() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/pinned-project", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 1, mode: .task)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .project(pinnedProject.persistentModelID), placement: .before)
        )

        XCTAssertTrue(didCommit)
        XCTAssertEqual(task.pinnedSortOrder, 0)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 1)
    }

    func testProjectDropRejectsPinnedTaskAnchor() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 0, mode: .task)
        fixture.context.insert(project)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(project.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .pinnedTask(task.persistentModelID), placement: .before)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(project.isPinned)
    }

    func testPinnedTaskDropRejectsProjectsSection() throws {
        let fixture = try SidebarTestFixture()
        let task = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 0, mode: .task)
        fixture.context.insert(task)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .projects, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 0)
    }

    func testPinnedTaskDropRejectsStaleArchivedDraftUnpinnedAndCrossDomainSources() throws {
        let fixture = try SidebarTestFixture()
        let owner = Project(path: "/tmp/project-owner", name: "Owner")
        let projectThread = AgentThread(
            name: "Project Thread",
            isPinned: true,
            pinnedSortOrder: 0,
            project: owner
        )
        owner.threads = [projectThread]
        let archived = AgentThread(name: "Archived", isPinned: true, archivedAt: Date(), mode: .task)
        let draft = AgentThread(name: "Draft", isPinned: true, isDraft: true, mode: .task)
        let unpinned = AgentThread(name: "Unpinned", mode: .task)
        let deleted = AgentThread(name: "Deleted", isPinned: true, mode: .task)
        fixture.context.insert(owner)
        for task in [archived, draft, unpinned, deleted] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        let deletedID = deleted.persistentModelID
        fixture.context.delete(deleted)
        try fixture.context.save()

        for dragItem in [
            SidebarDragItem.pinnedTask(deletedID),
            .pinnedTask(archived.persistentModelID),
            .pinnedTask(draft.persistentModelID),
            .pinnedTask(unpinned.persistentModelID),
            .pinnedTask(projectThread.persistentModelID)
        ] {
            XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
                dragItem: dragItem,
                target: SidebarDropTarget(section: .pinned, placement: .end)
            ))
        }

        let validTask = AgentThread(name: "Valid", isPinned: true, mode: .task)
        fixture.context.insert(validTask)
        try fixture.context.save()
        XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(validTask.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        ))
    }
}
