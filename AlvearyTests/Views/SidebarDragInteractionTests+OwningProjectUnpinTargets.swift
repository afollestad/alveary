import AppKit
import XCTest

@testable import Alveary

/// A pinned thread drags back onto its owning project group to unpin in place. The group is a
/// `.container` like every `.into` target, but pinned sources see exactly one — non-owning
/// projects publish nothing, so there is no invalid drop to reject.
@MainActor
extension SidebarDragInteractionTests {
    func testPinnedThreadDragTargetsOnlyItsOwningProjectGroup() throws {
        let fixture = try SidebarTestFixture()
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/unpin-source")
        let owner = try fixture.insertProject(name: "Owner", path: "/tmp/unpin-owner-group")
        let other = try fixture.insertProject(name: "Other", path: "/tmp/unpin-other-group")
        let sourceID = sourceThread.persistentModelID
        let ownerID = owner.persistentModelID
        let otherID = other.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, ownerID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.projects, ownerID): [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .projectHeader(.projects, otherID): [CGRect(x: 0, y: 150, width: 200, height: 24)],
            .projectTerminal(.projects, otherID): [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.pinnedThread(sourceID)],
            regularProjects: [.project(ownerID), .project(otherID)],
            owningProjectIDByPinnedThreadID: [sourceID: ownerID]
        )

        let candidates = sidebarProjectIntoDropCandidates(
            dragging: .pinnedThread(sourceID),
            geometry: geometry,
            viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
            logicalOrder: order
        )

        XCTAssertEqual(
            candidates.map(\.target),
            [SidebarDropTarget(section: .projects, item: .project(ownerID), placement: .into)]
        )
        XCTAssertEqual(candidates.first?.kind, .container)
    }

    func testPinnedThreadDragKeepsPinnedReorderBoundariesAlongsideTheUnpinContainer() throws {
        let fixture = try SidebarTestFixture()
        let sourceThread = try fixture.insertProject(name: "Source", path: "/tmp/unpin-mixed-source")
        let targetThread = try fixture.insertProject(name: "Target", path: "/tmp/unpin-mixed-target")
        let owner = try fixture.insertProject(name: "Owner", path: "/tmp/unpin-mixed-owner")
        let sourceID = sourceThread.persistentModelID
        let targetID = targetThread.persistentModelID
        let ownerID = owner.persistentModelID
        let sourceItem = SidebarDragItem.pinnedThread(sourceID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedThread(targetID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .projectHeader(.projects, ownerID): [CGRect(x: 0, y: 150, width: 200, height: 24)],
            .projectTerminal(.projects, ownerID): [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.pinnedThread(targetID), sourceItem],
            regularProjects: [.project(ownerID)],
            owningProjectIDByPinnedThreadID: [sourceID: ownerID]
        )

        // Reordering against Pinned neighbours stays the primary affordance.
        let reorderCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 41),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        // Inside the owning group — past the flat edge band — the unpin container wins.
        let unpinCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 180),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            reorderCandidate?.target,
            SidebarDropTarget(section: .pinned, item: .pinnedThread(targetID), placement: .before)
        )
        XCTAssertEqual(reorderCandidate?.kind, .boundary)
        XCTAssertEqual(
            unpinCandidate?.target,
            SidebarDropTarget(section: .projects, item: .project(ownerID), placement: .into)
        )
        XCTAssertEqual(unpinCandidate?.kind, .container)
    }

    func testPinnedTaskOwnProjectOffersTheUnpinContainerOnlyWhileUnpinnable() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertProject(name: "Task", path: "/tmp/unpin-task-source")
        let owner = try fixture.insertProject(name: "Owner", path: "/tmp/unpin-task-owner")
        let other = try fixture.insertProject(name: "Other", path: "/tmp/unpin-task-other")
        let taskID = task.persistentModelID
        let ownerID = owner.persistentModelID
        let otherID = other.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, ownerID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.projects, ownerID): [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .projectHeader(.projects, otherID): [CGRect(x: 0, y: 150, width: 200, height: 24)],
            .projectTerminal(.projects, otherID): [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        func candidates(unpinnable: Bool) -> [SidebarDragItem?] {
            sidebarProjectIntoDropCandidates(
                dragging: .pinnedTask(taskID),
                geometry: geometry,
                viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
                logicalOrder: SidebarDragLogicalOrder(
                    pinnedItems: [.pinnedTask(taskID)],
                    regularProjects: [.project(ownerID), .project(otherID)],
                    unpinnableTaskIDs: unpinnable ? [taskID] : [],
                    projectIDByTaskID: [taskID: ownerID]
                )
            ).map(\.target.item)
        }

        // Same gate as the `Tasks` container: a pinned Task missing from `unpinnableTaskIDs`
        // shows nothing on its own project — while other projects stay reparent targets either way.
        XCTAssertEqual(candidates(unpinnable: true), [.project(ownerID), .project(otherID)])
        XCTAssertEqual(candidates(unpinnable: false), [.project(otherID)])
    }
}
