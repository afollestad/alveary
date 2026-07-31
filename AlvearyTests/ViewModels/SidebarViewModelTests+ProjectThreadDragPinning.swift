import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testCommitSidebarDropPinsProjectThreadAtSectionEnd() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/pin-project-thread")
        let thread = AgentThread(name: "Thread", project: project)
        let pinnedProject = Project(path: "/tmp/pinned-anchor", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        fixture.context.insert(thread)
        fixture.context.insert(pinnedProject)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 0)
        XCTAssertEqual(thread.pinnedSortOrder, 1)
        // Pinning changes sidebar placement only; the thread still belongs to its project.
        XCTAssertEqual(thread.project?.persistentModelID, project.persistentModelID)
    }

    func testCommitSidebarDropPinsFirstProjectThreadIntoEmptyPinnedSection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/pin-first-project-thread")
        let thread = AgentThread(name: "Thread", project: project)
        fixture.context.insert(thread)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(thread.pinnedSortOrder, 0)
    }

    func testProjectThreadDropRejectsProjectsSection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/project-thread-no-projects")
        let thread = AgentThread(name: "Thread", project: project)
        fixture.context.insert(thread)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .projects, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.pinnedSortOrder)
    }

    func testProjectThreadDropRejectsTasksSection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/project-thread-no-tasks")
        let thread = AgentThread(name: "Thread", project: project)
        fixture.context.insert(thread)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(thread.isPinned)
        // A Tasks drop must not detach the thread from its project either.
        XCTAssertEqual(thread.project?.persistentModelID, project.persistentModelID)
    }

    func testProjectThreadUnderPinnedProjectRejectsPinning() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/pinned-parent", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let thread = AgentThread(name: "Thread", project: project)
        fixture.context.insert(project)
        fixture.context.insert(thread)
        try fixture.context.save()

        // A pinned parent absorbs child pins, so the standalone pin would be invisible and
        // normalization would clear it in the same commit.
        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(thread.isPinned)
    }

    func testTaskThreadIsNotAValidProjectThreadSource() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/project-thread-not-task")
        let task = AgentThread(name: "Task", mode: .task, project: project)
        fixture.context.insert(task)
        try fixture.context.save()

        // Mode mismatch: a Task dragged from a project is `.unpinnedTask`, never `.projectThread`.
        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .projectThread(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(task.isPinned)
    }
}
