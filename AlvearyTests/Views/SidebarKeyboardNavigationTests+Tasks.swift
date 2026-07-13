import XCTest

@testable import Alveary

@MainActor
extension SidebarKeyboardNavigationTests {
    func testBuildNavigableItemsPlacesTasksAfterProjects() {
        let pinnedTask = sidebarNavigationTask(name: "Pinned", isPinned: true)
        let project = Project(path: "/tmp/sidebar-navigation-project", name: "Project")
        let task = sidebarNavigationTask(name: "Task")

        let items = buildNavigableItems(
            pinnedItems: [SidebarPinnedItem(thread: pinnedTask)],
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            activeTasks: [task]
        )

        XCTAssertEqual(items, [
            .skills,
            .mcp,
            .thread(pinnedTask),
            .project(project),
            .thread(task)
        ])
    }

    func testBuildNavigableItemsIncludesTasksWhenThereAreNoProjects() {
        let task = sidebarNavigationTask(name: "Task")

        XCTAssertEqual(
            buildNavigableItems(
                projects: [],
                expandedProjects: [],
                activeThreads: { _ in [] },
                activeTasks: [task]
            ),
            [.skills, .mcp, .thread(task)]
        )
    }
}

@MainActor
private func sidebarNavigationTask(name: String, isPinned: Bool = false) -> AgentThread {
    AgentThread(
        name: name,
        isPinned: isPinned,
        mode: .task,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/\(UUID().uuidString)",
            ownershipStrategy: .projectLocal
        )
    )
}
