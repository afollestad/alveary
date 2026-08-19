import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testProjectChildDragDispatchesByMode() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/child-drag-modes")
        let projectThread = AgentThread(name: "Thread", project: project)
        let task = AgentThread(name: "Task", mode: .task, project: project)
        [projectThread, task].forEach(fixture.context.insert)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        // Both modes are sources; the dispatch only picks which drag item they carry.
        XCTAssertNotNil(view.projectChildDragConfiguration(for: projectThread, logicalOrder: emptySidebarDragLogicalOrder))
        XCTAssertNotNil(view.projectChildDragConfiguration(for: task, logicalOrder: emptySidebarDragLogicalOrder))
    }

    func testProjectThreadDragSourceGating() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/project-thread-gating")
        let pinnedProject = Project(path: "/tmp/pinned-parent-gating", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        fixture.context.insert(pinnedProject)
        let thread = AgentThread(name: "Thread", project: project)
        let pinned = AgentThread(name: "Pinned", isPinned: true, pinnedSortOrder: 1, project: project)
        let draft = AgentThread(name: "Draft", isDraft: true, project: project)
        let archived = AgentThread(name: "Archived", archivedAt: Date(), project: project)
        let absorbed = AgentThread(name: "Absorbed", project: pinnedProject)
        [thread, pinned, draft, archived, absorbed].forEach(fixture.context.insert)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        XCTAssertNotNil(view.projectChildDragConfiguration(for: thread, logicalOrder: emptySidebarDragLogicalOrder))
        // Pinned threads render in `Pinned` and drag as `.pinnedThread` from there.
        XCTAssertNil(view.projectChildDragConfiguration(for: pinned, logicalOrder: emptySidebarDragLogicalOrder))
        XCTAssertNil(view.projectChildDragConfiguration(for: draft, logicalOrder: emptySidebarDragLogicalOrder))
        XCTAssertNil(view.projectChildDragConfiguration(for: archived, logicalOrder: emptySidebarDragLogicalOrder))
        // A pinned parent absorbs child pins, so the drag's only destination would render
        // nothing; the source is withheld rather than offering a no-op drop.
        XCTAssertNil(view.projectChildDragConfiguration(for: absorbed, logicalOrder: emptySidebarDragLogicalOrder))
    }

    func testOwningProjectMapCoversEveryPinnedProjectModeThread() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/owning-map")
        let pinned = AgentThread(name: "Pinned", isPinned: true, pinnedSortOrder: 0, project: project)
        let pinnedTask = AgentThread(name: "Task", isPinned: true, pinnedSortOrder: 1, mode: .task, project: project)
        let attached = AgentThread(name: "Attached", isPinned: true, pinnedSortOrder: 2, project: project)
        [pinned, pinnedTask, attached].forEach(fixture.context.insert)
        fixture.context.insert(ScheduledTask(
            title: "Attached schedule",
            prompt: "Continue in the pinned thread.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: attached
        ))
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        // Pinned Tasks route through `projectIDByTaskID`; a scheduled attachment withholds
        // nothing, because a schedule never held its target's pin.
        XCTAssertEqual(
            view.owningProjectIDByPinnedThreadID(in: try fixture.renderSnapshot()),
            [
                pinned.persistentModelID: project.persistentModelID,
                attached.persistentModelID: project.persistentModelID
            ]
        )
    }
}

/// Drag configurations only need a logical order to seed a started session; these
/// assertions care about the configuration's existence, not the sidebar's order.
private let emptySidebarDragLogicalOrder = SidebarDragLogicalOrder(
    pinnedItems: [],
    regularProjects: []
)
