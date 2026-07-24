import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarRenderSnapshotTests: XCTestCase {
    func testSnapshotMembershipMatchesFetchBackedViewModelReads() throws {
        let fixture = try SidebarTestFixture()
        let alpha = Project(path: "/tmp/snapshot-alpha", name: "Alpha")
        let beta = Project(path: "/tmp/snapshot-beta", name: "Beta")
        let visible = makeSnapshotThread(name: "Visible", project: alpha)
        _ = makeSnapshotThread(name: "Draft", project: alpha, isDraft: true)
        _ = makeSnapshotThread(name: "Archived", project: alpha, archivedAt: Date())
        let task = makeSnapshotTask(name: "Task")
        fixture.context.insert(alpha)
        fixture.context.insert(beta)
        fixture.context.insert(task)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(
            snapshot.activeThreads(for: alpha).map(\.persistentModelID),
            fixture.viewModel.activeThreads(for: alpha).map(\.persistentModelID)
        )
        XCTAssertEqual(snapshot.activeThreads(for: alpha).map(\.persistentModelID), [visible.persistentModelID])
        XCTAssertTrue(snapshot.activeThreads(for: beta).isEmpty)
        XCTAssertTrue(snapshot.hasAnyActiveThreads(for: alpha))
        XCTAssertFalse(snapshot.hasAnyActiveThreads(for: beta))
        XCTAssertEqual(snapshot.activeTaskThreads.map(\.persistentModelID), [task.persistentModelID])
        XCTAssertTrue(snapshot.hasAnyActiveTaskThreads)
        XCTAssertEqual(
            snapshot.orderedProjects.map(\.path),
            fixture.viewModel.orderedProjects(from: [alpha, beta]).map(\.path)
        )
    }

    func testArchivedOnlyProjectSuppressesTheNoThreadsPlaceholder() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/snapshot-archived-only", name: "Archived Only")
        _ = makeSnapshotThread(name: "Archived", project: project, archivedAt: Date())
        fixture.context.insert(project)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        // Archived rows still count as "has threads", so the empty placeholder stays hidden.
        XCTAssertTrue(snapshot.activeThreads(for: project).isEmpty)
        XCTAssertFalse(snapshot.hasAnyActiveThreads(for: project))
        XCTAssertTrue(
            shouldShowNoThreadsPlaceholder(
                activeProjectThreads: snapshot.activeThreads(for: project),
                hasAnyActiveThreads: snapshot.hasAnyActiveThreads(for: project)
            )
        )
    }

    func testPinnedProjectAbsorbsItsChildrenWhileStandalonePinsStayTopLevel() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/snapshot-pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regularProject = Project(path: "/tmp/snapshot-regular", name: "Regular", sidebarSortOrder: 0)
        let absorbedChild = makeSnapshotThread(name: "Absorbed", project: pinnedProject, isPinned: true)
        let standalonePin = makeSnapshotThread(name: "Standalone", project: regularProject, isPinned: true)
        standalonePin.pinnedSortOrder = 1
        let unpinnedChild = makeSnapshotThread(name: "Unpinned", project: regularProject)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(
            snapshot.pinnedItems.map(\.id),
            ["project:\(pinnedProject.path)", "thread:\(String(describing: standalonePin.persistentModelID))"]
        )
        XCTAssertEqual(
            snapshot.activeThreads(for: pinnedProject).map(\.persistentModelID),
            [absorbedChild.persistentModelID]
        )
        // A standalone pinned child renders only in `Pinned`, never under its project.
        XCTAssertEqual(
            snapshot.activeThreads(for: regularProject).map(\.persistentModelID),
            [unpinnedChild.persistentModelID]
        )
        XCTAssertEqual(snapshot.regularProjects.map(\.path), [regularProject.path])
    }

    func testPinnedTasksStayIndependentOfTheirBackingProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/snapshot-task-project", name: "Task Project", isPinned: true, pinnedSortOrder: 0)
        let pinnedTask = makeSnapshotTask(name: "Pinned Task", isPinned: true)
        pinnedTask.project = project
        pinnedTask.pinnedSortOrder = 1
        let unpinnedTask = makeSnapshotTask(name: "Unpinned Task")
        unpinnedTask.project = project
        fixture.context.insert(project)
        fixture.context.insert(pinnedTask)
        fixture.context.insert(unpinnedTask)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(snapshot.pinnedItems.map(\.dragItem), [
            .project(project.persistentModelID),
            .pinnedTask(pinnedTask.persistentModelID)
        ])
        XCTAssertTrue(snapshot.activeThreads(for: project).isEmpty)
        XCTAssertEqual(snapshot.activeTaskThreads.map(\.persistentModelID), [unpinnedTask.persistentModelID])
    }

    func testLegacyActivityOrdersOnlyPinnedProjectsWithoutAManualOrder() throws {
        let fixture = try SidebarTestFixture()
        let stale = Project(path: "/tmp/snapshot-stale", name: "Stale", isPinned: true)
        let fresh = Project(path: "/tmp/snapshot-fresh", name: "Fresh", isPinned: true)
        _ = makeSnapshotThread(
            name: "Stale thread",
            project: stale,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        _ = makeSnapshotThread(
            name: "Fresh thread",
            project: fresh,
            modifiedAt: Date(timeIntervalSince1970: 900)
        )
        fixture.context.insert(stale)
        fixture.context.insert(fresh)
        try fixture.context.save()

        let legacySnapshot = try fixture.renderSnapshot()
        XCTAssertEqual(legacySnapshot.pinnedItems.map(\.stableID), [fresh.path, stale.path])

        // A manual order wins over activity, and later activity must not move the item.
        stale.pinnedSortOrder = 0
        fresh.pinnedSortOrder = 1
        try fixture.context.save()

        let manualSnapshot = try fixture.renderSnapshot()
        XCTAssertEqual(manualSnapshot.pinnedItems.map(\.stableID), [stale.path, fresh.path])
    }

    func testSnapshotRebuildsAfterProjectReassignmentAndModeChange() throws {
        let fixture = try SidebarTestFixture()
        let source = Project(path: "/tmp/snapshot-source", name: "Source")
        let destination = Project(path: "/tmp/snapshot-destination", name: "Destination")
        let thread = makeSnapshotThread(name: "Moving", project: source)
        fixture.context.insert(source)
        fixture.context.insert(destination)
        try fixture.context.save()

        XCTAssertEqual(try fixture.renderSnapshot().activeThreads(for: source).count, 1)

        thread.project = destination
        try fixture.context.save()

        let reassigned = try fixture.renderSnapshot()
        XCTAssertTrue(reassigned.activeThreads(for: source).isEmpty)
        XCTAssertEqual(reassigned.activeThreads(for: destination).map(\.persistentModelID), [thread.persistentModelID])

        thread.modeRawValue = AgentThreadMode.task.rawValue
        try fixture.context.save()

        let retyped = try fixture.renderSnapshot()
        XCTAssertTrue(retyped.activeThreads(for: destination).isEmpty)
        XCTAssertEqual(retyped.activeTaskThreads.map(\.persistentModelID), [thread.persistentModelID])
    }

    func testExpandedThreadCountFollowsExpansionAndPinnedRows() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/snapshot-count-pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regularProject = Project(path: "/tmp/snapshot-count-regular", name: "Regular", sidebarSortOrder: 0)
        _ = makeSnapshotThread(name: "Pinned child", project: pinnedProject)
        _ = makeSnapshotThread(name: "Regular child A", project: regularProject)
        _ = makeSnapshotThread(name: "Regular child B", project: regularProject)
        let standalonePin = makeSnapshotThread(name: "Standalone", project: regularProject, isPinned: true)
        standalonePin.pinnedSortOrder = 1
        let task = makeSnapshotTask(name: "Task")
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        fixture.context.insert(task)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        // Collapsed: one standalone pinned row plus one Task row.
        XCTAssertEqual(snapshot.expandedThreadCount(expandedProjects: []), 2)
        XCTAssertEqual(snapshot.expandedThreadCount(expandedProjects: [pinnedProject.path]), 3)
        XCTAssertEqual(
            snapshot.expandedThreadCount(expandedProjects: [pinnedProject.path, regularProject.path]),
            5
        )
    }

    func testKeyboardTraversalAndDragOrderComeFromTheSameSnapshot() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/snapshot-nav-pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regularProject = Project(path: "/tmp/snapshot-nav-regular", name: "Regular", sidebarSortOrder: 0)
        let pinnedChild = makeSnapshotThread(name: "Pinned child", project: pinnedProject)
        let regularChild = makeSnapshotThread(name: "Regular child", project: regularProject)
        let task = makeSnapshotTask(name: "Task")
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        fixture.context.insert(task)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()
        let items = buildNavigableItems(
            pinnedItems: snapshot.pinnedItems,
            projects: snapshot.regularProjects,
            expandedProjects: [pinnedProject.path, regularProject.path],
            activeThreads: snapshot.activeThreads(for:),
            activeTasks: snapshot.activeTaskThreads
        )

        XCTAssertEqual(items, [
            .skills,
            .mcp,
            .scheduled,
            .project(pinnedProject),
            .thread(pinnedChild),
            .project(regularProject),
            .thread(regularChild),
            .thread(task)
        ])
        XCTAssertEqual(snapshot.pinnedItems.map(\.dragItem), [.project(pinnedProject.persistentModelID)])
        XCTAssertEqual(
            snapshot.regularProjects.map { SidebarDragItem.project($0.persistentModelID) },
            [.project(regularProject.persistentModelID)]
        )
    }

    @discardableResult
    private func makeSnapshotThread(
        name: String,
        project: Project,
        isPinned: Bool = false,
        isDraft: Bool = false,
        archivedAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> AgentThread {
        let thread = AgentThread(
            name: name,
            isPinned: isPinned,
            isDraft: isDraft,
            modifiedAt: modifiedAt,
            archivedAt: archivedAt,
            project: project
        )
        project.threads.append(thread)
        return thread
    }

    private func makeSnapshotTask(name: String, isPinned: Bool = false) -> AgentThread {
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
}
