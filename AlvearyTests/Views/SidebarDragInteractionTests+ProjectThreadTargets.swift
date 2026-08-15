import AppKit
import XCTest

@testable import Alveary

/// A project-nested Project-mode thread drags only to pin: `Pinned` is its sole target, taken as
/// one appending container like a Task arriving from `Tasks`. It must see no `Projects`
/// boundaries, no `Tasks` container, and no `.into` project targets.
@MainActor
extension SidebarDragInteractionTests {
    func testProjectThreadDragTargetsThePinnedSectionWithoutExposingProjects() throws {
        let fixture = try SidebarTestFixture()
        let targetThread = try fixture.insertProject(name: "Target", path: "/tmp/pt-target")
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/pt-source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/pt-regular")
        let targetItem = SidebarDragItem.pinnedThread(targetThread.persistentModelID)
        let sourceItem = SidebarDragItem.projectThread(sourceThread.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 220)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedThread(targetThread.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .projectHeader(.projects, project.persistentModelID): [CGRect(x: 0, y: 150, width: 200, height: 24)],
            .projectTerminal(.projects, project.persistentModelID): [CGRect(x: 0, y: 150, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [targetItem],
            regularProjects: [.project(project.persistentModelID)]
        )

        let pinnedCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 38),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        let projectsCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 148),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        // Pinning is a membership choice, so the whole section is one container and the drop
        // appends — identical to a Task arriving from `Tasks`.
        XCTAssertEqual(pinnedCandidate?.kind, .container)
        XCTAssertEqual(
            pinnedCandidate?.target,
            SidebarDropTarget(section: .pinned, placement: .end)
        )
        XCTAssertNil(projectsCandidate)
    }

    func testProjectThreadDragSharesTheExtendedEmptyPinnedTarget() throws {
        let fixture = try SidebarTestFixture()
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/pt-empty-pinned")
        let sourceItem = SidebarDragItem.projectThread(sourceThread.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .topLevelTerminal: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 80, width: 200, height: 39.5)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: []
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        // The first pin has no section to aim at, so the hidden-pinned boundary above the
        // `Projects` header stands in — the same target every pin-creating source shares.
        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.kind, .boundary)
        XCTAssertEqual(candidate?.indicatorY, 80)
    }

    func testProjectThreadDragSeesNoTasksContainer() throws {
        let fixture = try SidebarTestFixture()
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/pt-no-tasks")
        let sourceItem = SidebarDragItem.projectThread(sourceThread.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 140, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 164, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: []
        )

        // A project thread has no Tasks membership to choose; the only candidate anywhere near
        // the Tasks section is nothing at all.
        XCTAssertNil(
            sidebarDropCandidateForLocation(
                at: CGPoint(x: 100, y: 152),
                dragging: sourceItem,
                geometry: geometry,
                logicalOrder: order
            )
        )
    }

    func testProjectThreadDragSeesNoIntoProjectTargets() throws {
        let fixture = try SidebarTestFixture()
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/pt-no-into")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/pt-into-project")
        let sourceItem = SidebarDragItem.projectThread(sourceThread.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, project.persistentModelID): [CGRect(x: 0, y: 50, width: 200, height: 24)],
            .projectTerminal(.projects, project.persistentModelID): [CGRect(x: 0, y: 74, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(project.persistentModelID)]
        )

        // `.into` reparents a Task and grants folder access; a project thread already lives in
        // its project, so no project group may present a container to it.
        XCTAssertTrue(
            sidebarProjectIntoDropCandidates(
                dragging: sourceItem,
                geometry: geometry,
                viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
                logicalOrder: order
            ).isEmpty
        )
    }
}
