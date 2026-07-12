import XCTest

@testable import Alveary

@MainActor
final class SidebarKeyboardNavigationOrderingTests: XCTestCase {
    func testPersistedMixedOrderDrivesTraversalAndKeepsExpandedChildrenContiguous() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(
            path: "/tmp/pinned-project",
            name: "Pinned Project",
            isPinned: true,
            pinnedSortOrder: 1
        )
        let pinnedChild = AgentThread(name: "Pinned Child", project: pinnedProject)
        pinnedProject.threads = [pinnedChild]
        let regularProject = Project(path: "/tmp/regular", name: "Regular", sidebarSortOrder: 0)
        let standalonePinned = AgentThread(
            name: "Standalone",
            isPinned: true,
            pinnedSortOrder: 0,
            project: regularProject
        )
        let regularChild = AgentThread(name: "Regular Child", project: regularProject)
        regularProject.threads = [standalonePinned, regularChild]
        let trailingProject = Project(path: "/tmp/trailing", name: "Trailing", sidebarSortOrder: 1)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        fixture.context.insert(trailingProject)
        try fixture.context.save()

        let items = buildNavigableItems(
            pinnedItems: fixture.viewModel.pinnedItems(projects: [pinnedProject, regularProject, trailingProject]),
            projects: fixture.viewModel.regularProjects(from: [trailingProject, regularProject, pinnedProject]),
            expandedProjects: [pinnedProject.path, regularProject.path],
            activeThreads: fixture.viewModel.activeThreads(for:)
        )

        XCTAssertEqual(items, [
            .skills,
            .mcp,
            .thread(standalonePinned),
            .project(pinnedProject),
            .thread(pinnedChild),
            .project(regularProject),
            .thread(regularChild),
            .project(trailingProject)
        ])
    }

    func testNavigationUsesNewNeighborsAfterPersistedProjectDrop() throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", sidebarSortOrder: 0)
        let second = Project(path: "/tmp/second", name: "Second", sidebarSortOrder: 1)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        XCTAssertTrue(try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(second.persistentModelID),
            target: SidebarDropTarget(
                section: .projects,
                item: .project(first.persistentModelID),
                placement: .before
            )
        ))
        let orderedProjects = fixture.viewModel.regularProjects(from: [first, second])
        let items = buildNavigableItems(
            projects: orderedProjects,
            expandedProjects: [],
            activeThreads: { _ in [] }
        )

        XCTAssertEqual(navigateVertically(in: items, from: .project(second), forward: true), .project(first))
    }
}
