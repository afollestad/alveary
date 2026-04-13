import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarKeyboardNavigationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // MARK: - buildNavigableItems

    func testBuildNavigableItemsWithNoProjects() {
        let items = buildNavigableItems(projects: [], expandedProjects: [], activeThreads: { _ in [] })

        XCTAssertEqual(items, [.skills, .mcp])
    }

    func testBuildNavigableItemsWithCollapsedProjects() throws {
        let projectA = makeProject(name: "Alpha", path: "/tmp/alpha")
        let projectB = makeProject(name: "Beta", path: "/tmp/beta")
        makeThread(name: "Thread 1", project: projectA)
        try context.save()

        let items = buildNavigableItems(
            projects: [projectA, projectB],
            expandedProjects: [],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil }
            }
        )

        XCTAssertEqual(items, [.skills, .mcp, .project(projectA), .project(projectB)])
    }

    func testBuildNavigableItemsWithExpandedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: ["/tmp/alpha"],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil }
            }
        )

        XCTAssertEqual(items, [.skills, .mcp, .project(project), .thread(thread)])
    }

    func testBuildNavigableItemsExcludesArchivedThreads() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let active = makeThread(name: "Active", project: project)
        makeThread(name: "Archived", project: project, archivedAt: Date())
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: ["/tmp/alpha"],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil }
            }
        )

        XCTAssertEqual(items, [.skills, .mcp, .project(project), .thread(active)])
    }

    func testBuildNavigableItemsMixedExpandedAndCollapsed() throws {
        let projectA = makeProject(name: "Alpha", path: "/tmp/alpha")
        let projectB = makeProject(name: "Beta", path: "/tmp/beta")
        let threadA = makeThread(name: "Thread A", project: projectA)
        makeThread(name: "Thread B", project: projectB)
        try context.save()

        let items = buildNavigableItems(
            projects: [projectA, projectB],
            expandedProjects: ["/tmp/alpha"],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil }
            }
        )

        XCTAssertEqual(items, [.skills, .mcp, .project(projectA), .thread(threadA), .project(projectB)])
    }

    // MARK: - navigateVertically

    func testNavigateDownFromNilSelectsFirstItem() {
        let items: [SidebarItem] = [.skills, .mcp]

        let result = navigateVertically(in: items, from: nil, forward: true)

        XCTAssertEqual(result, .skills)
    }

    func testNavigateDownThroughItems() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)
        try context.save()

        let items: [SidebarItem] = [.skills, .mcp, .project(project), .thread(thread)]

        XCTAssertEqual(navigateVertically(in: items, from: .skills, forward: true), .mcp)
        XCTAssertEqual(navigateVertically(in: items, from: .mcp, forward: true), .project(project))
        XCTAssertEqual(navigateVertically(in: items, from: .project(project), forward: true), .thread(thread))
    }

    func testNavigateDownAtEndReturnsNil() {
        let result = navigateVertically(in: [.skills, .mcp], from: .mcp, forward: true)

        XCTAssertNil(result)
    }

    func testNavigateUpThroughItems() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)
        try context.save()

        let items: [SidebarItem] = [.skills, .mcp, .project(project), .thread(thread)]

        XCTAssertEqual(navigateVertically(in: items, from: .thread(thread), forward: false), .project(project))
        XCTAssertEqual(navigateVertically(in: items, from: .project(project), forward: false), .mcp)
        XCTAssertEqual(navigateVertically(in: items, from: .mcp, forward: false), .skills)
    }

    func testNavigateUpAtTopReturnsNil() {
        let result = navigateVertically(in: [.skills, .mcp], from: .skills, forward: false)

        XCTAssertNil(result)
    }

    func testNavigateUpFromNilReturnsNil() {
        let result = navigateVertically(in: [.skills, .mcp], from: nil, forward: false)

        XCTAssertNil(result)
    }

    func testNavigateInEmptyListReturnsNil() {
        XCTAssertNil(navigateVertically(in: [], from: nil, forward: true))
        XCTAssertNil(navigateVertically(in: [], from: nil, forward: false))
    }

    func testNavigateDownFromUnrecognizedSelectionSelectsFirst() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items: [SidebarItem] = [.skills, .mcp, .project(project)]
        let result = navigateVertically(in: items, from: .settings, forward: true)

        XCTAssertEqual(result, .skills)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeProject(name: String, path: String) -> Project {
        let project = Project(path: path, name: name)
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeThread(name: String, project: Project, archivedAt: Date? = nil) -> AgentThread {
        let thread = AgentThread(name: name, archivedAt: archivedAt, project: project)
        let conversation = Conversation(
            id: UUID().uuidString,
            title: "Main",
            provider: "claude",
            thread: thread
        )
        thread.conversations = [conversation]
        project.threads.append(thread)
        return thread
    }
}
