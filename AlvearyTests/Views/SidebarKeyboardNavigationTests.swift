import Foundation
import SwiftData
import XCTest

@testable import Alveary

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

    func testBuildNavigableItemsPlacesPinnedThreadsAfterMCPBeforeProjects() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let pinned = makeThread(name: "Pinned", project: project, isPinned: true)
        try context.save()

        let items = buildNavigableItems(
            pinnedItems: [SidebarPinnedItem(thread: pinned)],
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] }
        )

        XCTAssertEqual(items, [.skills, .mcp, .thread(pinned), .project(project)])
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

    func testBuildNavigableItemsDoesNotDuplicatePinnedThreadsUnderExpandedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let pinned = makeThread(name: "Pinned", project: project, isPinned: true)
        let unpinned = makeThread(name: "Unpinned", project: project)
        try context.save()

        let items = buildNavigableItems(
            pinnedItems: [SidebarPinnedItem(thread: pinned)],
            projects: [project],
            expandedProjects: ["/tmp/alpha"],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil && !$0.isPinned }
            }
        )

        XCTAssertEqual(items, [.skills, .mcp, .thread(pinned), .project(project), .thread(unpinned)])
    }

    func testBuildNavigableItemsIncludesExpandedPinnedProjectChildrenBeforeRegularProjects() throws {
        let pinnedProject = makeProject(name: "Pinned", path: "/tmp/pinned", isPinned: true)
        let pinnedProjectChild = makeThread(name: "Pinned Child", project: pinnedProject)
        let regularProject = makeProject(name: "Regular", path: "/tmp/regular")
        let regularProjectChild = makeThread(name: "Regular Child", project: regularProject)
        try context.save()

        let items = buildNavigableItems(
            pinnedItems: [SidebarPinnedItem(project: pinnedProject, activityDate: nil)],
            projects: [regularProject],
            expandedProjects: ["/tmp/pinned", "/tmp/regular"],
            activeThreads: { project in
                project.threads.filter { $0.archivedAt == nil && !$0.isPinned }
            }
        )

        XCTAssertEqual(items, [
            .skills,
            .mcp,
            .project(pinnedProject),
            .thread(pinnedProjectChild),
            .project(regularProject),
            .thread(regularProjectChild)
        ])
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

    func testShouldNavigateUpOnLeftArrowReturnsTrueForThreadSelection() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)

        let result = shouldNavigateUpOnLeftArrow(
            selection: .thread(thread),
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsTrueForSkillsSelection() {
        let result = shouldNavigateUpOnLeftArrow(
            selection: .skills,
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsTrueForMCPSelection() {
        let result = shouldNavigateUpOnLeftArrow(
            selection: .mcp,
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsFalseForExpandedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = shouldNavigateUpOnLeftArrow(
            selection: .project(project),
            expandedProjects: [project.path]
        )

        XCTAssertFalse(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsTrueForExpandedProjectWithoutVisibleThreads() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = shouldNavigateUpOnLeftArrow(
            selection: .project(project),
            expandedProjects: [project.path],
            projectHasVisibleThreads: { _ in false }
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsTrueForCollapsedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = shouldNavigateUpOnLeftArrow(
            selection: .project(project),
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateUpOnLeftArrowReturnsFalseForTopLevelSelection() {
        let result = shouldNavigateUpOnLeftArrow(
            selection: .settings,
            expandedProjects: []
        )

        XCTAssertFalse(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsFalseForCollapsedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = shouldNavigateDownOnRightArrow(
            selection: .project(project),
            expandedProjects: []
        )

        XCTAssertFalse(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsTrueForExpandedProject() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = shouldNavigateDownOnRightArrow(
            selection: .project(project),
            expandedProjects: [project.path]
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsTrueForThreadSelection() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)

        let result = shouldNavigateDownOnRightArrow(
            selection: .thread(thread),
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsTrueForSkillsSelection() {
        let result = shouldNavigateDownOnRightArrow(
            selection: .skills,
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsTrueForMCPSelection() {
        let result = shouldNavigateDownOnRightArrow(
            selection: .mcp,
            expandedProjects: []
        )

        XCTAssertTrue(result)
    }

    func testShouldNavigateDownOnRightArrowReturnsFalseForTopLevelSelection() {
        let result = shouldNavigateDownOnRightArrow(
            selection: .settings,
            expandedProjects: []
        )

        XCTAssertFalse(result)
    }

    func testRenameThreadIDReturnsSelectedThreadIDWhenNotEditing() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)

        let result = renameThreadID(
            for: .thread(thread),
            editingThreadID: nil
        )

        XCTAssertEqual(result, thread.persistentModelID)
    }

    func testRenameThreadIDReturnsNilForNonThreadSelection() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")

        let result = renameThreadID(
            for: .project(project),
            editingThreadID: nil
        )

        XCTAssertNil(result)
    }

    func testShouldSuppressSidebarKeyPressWhileRenamingReturnsTrueWhenEditing() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)

        XCTAssertTrue(shouldSuppressSidebarKeyPressWhileRenaming(editingThreadID: thread.persistentModelID))
    }

    func testShouldSuppressSidebarKeyPressWhileRenamingReturnsFalseWhenIdle() {
        XCTAssertFalse(shouldSuppressSidebarKeyPressWhileRenaming(editingThreadID: nil))
    }

    func testRenameThreadIDReturnsNilWhileEditingAnotherThread() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        let thread = makeThread(name: "Thread 1", project: project)
        let editingThread = makeThread(name: "Thread 2", project: project)

        let result = renameThreadID(
            for: .thread(thread),
            editingThreadID: editingThread.persistentModelID
        )

        XCTAssertNil(result)
    }

    func testSidebarThreadRenameCommitValueIgnoresEmptySubmission() {
        XCTAssertNil(sidebarThreadRenameCommitValue(
            initialValue: "Generated Provider Title",
            submittedValue: "   "
        ))
    }

    func testSidebarThreadRenameCommitValueIgnoresUnchangedDefaultName() {
        XCTAssertNil(sidebarThreadRenameCommitValue(
            initialValue: "New thread",
            submittedValue: "New thread"
        ))
    }

    func testSidebarThreadRenameCommitValueIgnoresUnchangedNonDefaultName() {
        XCTAssertNil(sidebarThreadRenameCommitValue(
            initialValue: "Generated Provider Title",
            submittedValue: "Generated Provider Title"
        ))
    }

    func testSidebarThreadRenameCommitValueIgnoresWhitespaceOnlyDifference() {
        XCTAssertNil(sidebarThreadRenameCommitValue(
            initialValue: "Generated Provider Title",
            submittedValue: "  Generated Provider Title  "
        ))
    }

    func testSidebarThreadRenameCommitValueReturnsTrimmedChangedName() {
        XCTAssertEqual(
            sidebarThreadRenameCommitValue(
                initialValue: "Generated Provider Title",
                submittedValue: "  Manual Title  "
            ),
            "Manual Title"
        )
    }

    // MARK: - Helpers

    @discardableResult
    private func makeProject(name: String, path: String, isPinned: Bool = false) -> Project {
        let project = Project(path: path, name: name, isPinned: isPinned)
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeThread(name: String, project: Project, archivedAt: Date? = nil, isPinned: Bool = false) -> AgentThread {
        let thread = AgentThread(name: name, isPinned: isPinned, archivedAt: archivedAt, project: project)
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
