import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarSectionCollapseTests: XCTestCase {
    // MARK: - Traversal

    func testCollapsedProjectsSectionDropsItsRowsAndChildrenFromTraversal() {
        let project = Project(path: "/tmp/collapse-projects", name: "Alpha")
        let child = makeProjectThread(name: "Child", project: project)

        let expanded = buildNavigableItems(
            projects: [project],
            expandedProjects: [project.path],
            activeThreads: { _ in [child] },
            collapsedSections: []
        )
        let collapsed = buildNavigableItems(
            projects: [project],
            expandedProjects: [project.path],
            activeThreads: { _ in [child] },
            collapsedSections: [.projects]
        )

        XCTAssertEqual(expanded, [.skills, .mcp, .scheduled, .pullRequests, .project(project), .thread(child)])
        XCTAssertEqual(collapsed, [.skills, .mcp, .scheduled, .pullRequests])
    }

    func testCollapsedTasksSectionDropsTaskRowsFromTraversal() {
        let task = makeTask(name: "Task")

        let collapsed = buildNavigableItems(
            projects: [],
            expandedProjects: [],
            activeThreads: { _ in [] },
            activeTasks: [task],
            collapsedSections: [.tasks]
        )

        XCTAssertEqual(collapsed, [.skills, .mcp, .scheduled, .pullRequests])
    }

    // `Pinned` has no header collapse of its own, so nothing may drop its rows.
    func testCollapsedSectionsLeavePinnedRowsTraversable() {
        let pinnedProject = Project(path: "/tmp/collapse-pinned", name: "Pinned", isPinned: true)
        let pinnedChild = makeProjectThread(name: "Pinned child", project: pinnedProject)

        let items = buildNavigableItems(
            pinnedItems: [SidebarPinnedItem(project: pinnedProject, activityDate: nil)],
            projects: [],
            expandedProjects: [pinnedProject.path],
            activeThreads: { _ in [pinnedChild] },
            collapsedSections: [.projects, .tasks]
        )

        XCTAssertEqual(items, [
            .skills,
            .mcp,
            .scheduled,
            .pullRequests,
            .project(pinnedProject),
            .thread(pinnedChild)
        ])
    }

    // MARK: - Selection reveal

    // The counterpart to `testProjectSelectionDoesNotExpandItsOwnRow`: traversal can rest on a
    // collapsed project row, but not inside a collapsed section, so a selection landing there was
    // routed explicitly and has to be revealed.
    func testSelectingARegularProjectReopensItsSection() {
        let project = Project(path: "/tmp/reveal-regular", name: "Alpha")

        XCTAssertEqual(sidebarSectionToExpand(for: .project(project), resolveThread: { _ in nil }), .projects)
    }

    func testSelectingAPinnedProjectReopensNothing() {
        let project = Project(path: "/tmp/reveal-pinned", name: "Pinned", isPinned: true)

        XCTAssertNil(sidebarSectionToExpand(for: .project(project), resolveThread: { _ in nil }))
    }

    func testSelectingAProjectlessTaskReopensTheTasksSection() {
        let task = makeTask(name: "Task")

        XCTAssertEqual(sidebarSectionToExpand(for: .thread(task), resolveThread: { _ in task }), .tasks)
    }

    func testSelectingAPinnedTaskReopensNothing() {
        let task = makeTask(name: "Pinned task", isPinned: true)

        XCTAssertNil(sidebarSectionToExpand(for: .thread(task), resolveThread: { _ in task }))
    }

    func testSelectingAProjectChildReopensTheProjectsSection() {
        let project = Project(path: "/tmp/reveal-child", name: "Alpha")
        let child = makeProjectThread(name: "Child", project: project)

        XCTAssertEqual(sidebarSectionToExpand(for: .thread(child), resolveThread: { _ in child }), .projects)
    }

    // A pinned project's children render inside it under `Pinned`, and a standalone pinned thread
    // renders there too; neither is hidden by a collapsed `Projects`.
    func testSelectingAThreadRenderedUnderPinnedReopensNothing() {
        let pinnedProject = Project(path: "/tmp/reveal-pinned-parent", name: "Pinned", isPinned: true)
        let pinnedChild = makeProjectThread(name: "Pinned child", project: pinnedProject)
        let regularProject = Project(path: "/tmp/reveal-standalone-parent", name: "Alpha")
        let standalonePin = makeProjectThread(name: "Standalone", project: regularProject, isPinned: true)

        XCTAssertNil(sidebarSectionToExpand(for: .thread(pinnedChild), resolveThread: { _ in pinnedChild }))
        XCTAssertNil(sidebarSectionToExpand(for: .thread(standalonePin), resolveThread: { _ in standalonePin }))
    }

    func testTopLevelSelectionReopensNothing() {
        for item in [SidebarItem.skills, .mcp, .scheduled, .pullRequests, .archived] {
            XCTAssertNil(sidebarSectionToExpand(for: item, resolveThread: { _ in nil }), "\(item)")
        }
        XCTAssertNil(sidebarSectionToExpand(for: nil, resolveThread: { _ in nil }))
    }

    // MARK: - Drop sections

    func testEveryCollapsibleDropSectionMapsBackExceptPinned() {
        XCTAssertEqual(SidebarCollapsibleSection(dropSection: .projects), .projects)
        XCTAssertEqual(SidebarCollapsibleSection(dropSection: .tasks), .tasks)
        XCTAssertNil(SidebarCollapsibleSection(dropSection: .pinned))
    }

    // MARK: - Helpers

    @discardableResult
    private func makeProjectThread(name: String, project: Project, isPinned: Bool = false) -> AgentThread {
        let thread = AgentThread(name: name, isPinned: isPinned, project: project)
        project.threads.append(thread)
        return thread
    }

    private func makeTask(name: String, isPinned: Bool = false) -> AgentThread {
        AgentThread(
            name: name,
            isPinned: isPinned,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/collapse-task-root",
                ownershipStrategy: .projectLocal,
                sourceProjectPath: "/tmp/collapse-task-root"
            )
        )
    }
}
