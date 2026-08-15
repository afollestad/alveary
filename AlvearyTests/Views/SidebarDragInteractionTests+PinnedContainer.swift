import AppKit
import XCTest

@testable import Alveary

/// `Pinned` presents itself as one container to a Task arriving from `Tasks`, rather than the
/// insertion boundaries its own members reorder against.
@MainActor
extension SidebarDragInteractionTests {
    func testUnpinnedTaskDragTargetsThePinnedSectionWithoutExposingProjects() throws {
        let fixture = try SidebarTestFixture()
        let targetThread = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/regular")
        let targetItem = SidebarDragItem.pinnedThread(targetThread.persistentModelID)
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
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

        // Arriving from `Tasks` is a membership choice, not a position one, so the whole section
        // is one container and the drop appends.
        XCTAssertEqual(pinnedCandidate?.kind, .container)
        XCTAssertEqual(
            pinnedCandidate?.target,
            SidebarDropTarget(section: .pinned, placement: .end)
        )
        // Header through last pinned item, outset for breathing room like the `Tasks` container.
        // The union is [6, 64]; the top outset clips against the viewport.
        XCTAssertEqual(
            pinnedCandidate?.hitFrame,
            CGRect(x: 0, y: 0, width: 200, height: 64 + SidebarDropTargetingMetrics.containerOutset)
        )
        XCTAssertNil(projectsCandidate)
    }

    func testPinnedAndTasksContainersInsetIdentically() throws {
        let fixture = try SidebarTestFixture()
        let pinnedTask = try fixture.insertProject(name: "Pinned", path: "/tmp/inset-pinned")
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/inset-source")
        let pinnedID = pinnedTask.persistentModelID
        let sourceID = sourceTask.persistentModelID
        // Both sections laid out identically: a 24pt title row, then one 24pt content row.
        let header = CGRect(x: 0, y: 40, width: 200, height: 24)
        let row = CGRect(x: 0, y: 64, width: 200, height: 24)
        let shifted = CGRect(x: 0, y: 140, width: 200, height: 24)
        let shiftedRow = CGRect(x: 0, y: 164, width: 200, height: 24)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [header],
            .pinnedTask(pinnedID): [row],
            .projectsHeader: [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .tasksHeader: [shifted],
            .tasksTerminal: [shiftedRow]
        ]

        let pinnedContainer = sidebarPinnedSectionContainerCandidate(
            dragging: .unpinnedTask(sourceID),
            geometry: geometry,
            viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.pinnedTask(pinnedID)],
                regularProjects: []
            )
        )
        let tasksContainer = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 170),
            dragging: .pinnedTask(pinnedID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.pinnedTask(pinnedID)],
                regularProjects: [],
                unpinnableTaskIDs: [pinnedID]
            )
        )

        // Same content shape must give the same border box, offset only by where it sits.
        let pinnedFrame = try XCTUnwrap(pinnedContainer?.borderFrame)
        let tasksFrame = try XCTUnwrap(tasksContainer?.borderFrame)
        XCTAssertEqual(tasksContainer?.kind, .container)
        XCTAssertEqual(pinnedFrame.size, tasksFrame.size)
        XCTAssertEqual(pinnedFrame.minY - header.minY, tasksFrame.minY - shifted.minY)
    }

    func testPinnedSectionContainerYieldsToANestedProjectGroup() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/nested-source")
        let project = try fixture.insertProject(name: "Pinned project", path: "/tmp/nested-project")
        let projectID = project.persistentModelID
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 34, width: 200, height: 20)],
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.project(projectID)],
            regularProjects: []
        )

        let overHeader = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 45),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        let insideProject = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 95),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        // Both containers score a perfect hit, so `.into` has to win the tie on priority —
        // otherwise a pinned project could never accept a reparent drop.
        XCTAssertEqual(overHeader?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(
            insideProject?.target,
            SidebarDropTarget(section: .pinned, item: .project(projectID), placement: .into)
        )
    }
}
