import AppKit
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testMonitorCancellationRoutesPinnedTaskSession() throws {
        let fixture = try SidebarTestFixture()
        let model = try fixture.insertProject(name: "Task", path: "/tmp/monitor-task")
        let item = SidebarDragItem.pinnedTask(model.persistentModelID)
        let session = SidebarDragSession(
            id: UUID(),
            item: item,
            location: CGPoint(x: 100, y: 100),
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [item],
                regularProjects: [],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(
            sidebarDragMonitorAction(
                eventType: .keyDown,
                keyCode: 53,
                interactionState: .active(session),
                originatesInWindow: true
            ),
            .escape
        )
        XCTAssertEqual(sidebarDragStateAfterEscape(.active(session)), .cancelledUntilMouseUp(session.id))
        XCTAssertEqual(
            sidebarDragMonitorAction(
                eventType: .leftMouseUp,
                keyCode: 0,
                interactionState: .cancelledUntilMouseUp(session.id),
                originatesInWindow: true
            ),
            .mouseUp
        )
        XCTAssertEqual(sidebarDragStateAfterCancelledMouseUp(.cancelledUntilMouseUp(session.id)), .idle)
    }

    func testPinnedTaskDragTargetsMixedPinnedItemsWithoutExposingProjects() throws {
        let fixture = try SidebarTestFixture()
        let targetThread = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/regular")
        let targetItem = SidebarDragItem.pinnedThread(targetThread.persistentModelID)
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 220)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedThread(targetThread.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .pinnedTask(sourceTask.persistentModelID): [CGRect(x: 0, y: 80, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .projectHeader(.projects, project.persistentModelID): [CGRect(x: 0, y: 150, width: 200, height: 24)],
            .projectTerminal(.projects, project.persistentModelID): [CGRect(x: 0, y: 150, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [targetItem, sourceItem],
            regularProjects: [.project(project.persistentModelID)],
            projectsHeaderIsSticky: false
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

        XCTAssertEqual(
            pinnedCandidate?.target,
            SidebarDropTarget(section: .pinned, item: targetItem, placement: .before)
        )
        XCTAssertNil(projectsCandidate)
    }

    func testUnpinnedTaskDragWithEmptyPinnedUsesHiddenPinnedTargetAtProjectsHeader() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/regular")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(project.persistentModelID)],
            projectsHeaderIsSticky: true
        )

        let pinnedEnd = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 44),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        let lowerHalf = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 60),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(pinnedEnd?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertNil(lowerHalf)
    }

    func testPinnedTaskDragExposesTasksTargetOnlyWhenUnpinnable() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/regular")
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedTask(sourceTask.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 230, width: 200, height: 24)]
        ]
        let unpinnableOrder = SidebarDragLogicalOrder(
            pinnedItems: [sourceItem],
            regularProjects: [.project(project.persistentModelID)],
            projectsHeaderIsSticky: false,
            unpinnableTaskIDs: [sourceTask.persistentModelID]
        )
        let attachedOrder = SidebarDragLogicalOrder(
            pinnedItems: [sourceItem],
            regularProjects: [.project(project.persistentModelID)],
            projectsHeaderIsSticky: false
        )

        let tasksCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 218),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: unpinnableOrder
        )
        let attachedCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 218),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: attachedOrder
        )

        // The Tasks target is a container spanning header through last row, so a drop lands
        // anywhere inside it — including below the header, far from any insertion boundary.
        let deepCandidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 248),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: unpinnableOrder
        )

        XCTAssertEqual(tasksCandidate?.target, SidebarDropTarget(section: .tasks, placement: .end))
        XCTAssertEqual(tasksCandidate?.kind, .container)
        // Outset by `containerOutset` so the border does not hug the header text.
        let outset = SidebarDropTargetingMetrics.containerOutset
        XCTAssertEqual(
            tasksCandidate?.hitFrame,
            CGRect(x: 0, y: 200 - outset, width: 200, height: 54 + outset * 2)
        )
        XCTAssertEqual(deepCandidate?.target, SidebarDropTarget(section: .tasks, placement: .end))
        XCTAssertNil(attachedCandidate)
    }

    func testTasksContainerSurvivesItsMidpointScrollingOutOfView() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        // The section starts just above the viewport bottom; its unclipped midpoint is below it.
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedTask(sourceTask.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 180, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 210, width: 200, height: 100)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [sourceItem],
            regularProjects: [],
            projectsHeaderIsSticky: false,
            unpinnableTaskIDs: [sourceTask.persistentModelID]
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 190),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .tasks, placement: .end))
        XCTAssertEqual(
            candidate?.hitFrame,
            CGRect(x: 0, y: 180 - SidebarDropTargetingMetrics.containerOutset, width: 200, height: 20 + SidebarDropTargetingMetrics.containerOutset)
        )
        XCTAssertEqual(candidate?.indicatorY, 190 - SidebarDropTargetingMetrics.containerOutset / 2)
    }

    func testTasksContainerFallsBackToHeaderWithoutTerminalGeometry() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedTask(sourceTask.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [sourceItem],
            regularProjects: [],
            projectsHeaderIsSticky: false,
            unpinnableTaskIDs: [sourceTask.persistentModelID]
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 210),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        let outset = SidebarDropTargetingMetrics.containerOutset
        XCTAssertEqual(
            candidate?.hitFrame,
            CGRect(x: 0, y: 200 - outset, width: 200, height: 24 + outset * 2)
        )
        XCTAssertEqual(candidate?.kind, .container)
    }

    func testPinnedBoundariesStayInsertionLinesDuringTaskDrags() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let anchor = try fixture.insertProject(name: "Anchor", path: "/tmp/anchor")
        let anchorItem = SidebarDragItem.pinnedThread(anchor.persistentModelID)
        // A source already inside `Pinned` is reordering, so it keeps insertion lines. An
        // unpinned Task arriving from `Tasks` takes the section container instead.
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedThread(anchor.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [anchorItem],
            regularProjects: [],
            projectsHeaderIsSticky: false
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 38),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(candidate?.kind, .boundary)
        XCTAssertEqual(
            candidate?.target,
            SidebarDropTarget(section: .pinned, item: anchorItem, placement: .before)
        )
    }

    func testDragBorderLocalRectClampsToOverlay() throws {
        let viewport = CGRect(x: 0, y: 100, width: 200, height: 200)
        let overlaySize = CGSize(width: 200, height: 200)

        let inside = sidebarDragBorderLocalRect(
            frame: CGRect(x: 0, y: 140, width: 200, height: 60),
            viewport: viewport,
            overlaySize: overlaySize
        )
        let scrolledAbove = sidebarDragBorderLocalRect(
            frame: CGRect(x: 0, y: 60, width: 200, height: 80),
            viewport: viewport,
            overlaySize: overlaySize
        )

        XCTAssertEqual(inside, CGRect(x: 3, y: 40, width: 194, height: 60))
        // A container scrolled partly out of view still borders its visible extent.
        XCTAssertEqual(scrolledAbove, CGRect(x: 3, y: 0, width: 194, height: 40))
    }

    func testTasksTargetHiddenForNonPinnedTaskSources() throws {
        let fixture = try SidebarTestFixture()
        let pinnedThread = try fixture.insertProject(name: "Pinned Thread", path: "/tmp/pinned-thread")
        let unpinnedTask = try fixture.insertProject(name: "Unpinned Task", path: "/tmp/unpinned-task")
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .pinnedThread(pinnedThread.persistentModelID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.pinnedThread(pinnedThread.persistentModelID)],
            regularProjects: [],
            projectsHeaderIsSticky: false,
            unpinnableTaskIDs: [pinnedThread.persistentModelID, unpinnedTask.persistentModelID]
        )

        for sourceItem in [
            SidebarDragItem.pinnedThread(pinnedThread.persistentModelID),
            .unpinnedTask(unpinnedTask.persistentModelID)
        ] {
            XCTAssertNil(sidebarDropCandidateForLocation(
                at: CGPoint(x: 100, y: 218),
                dragging: sourceItem,
                geometry: geometry,
                logicalOrder: order
            ))
        }
    }

    func testUnpinnedTaskBoundaryFramesAreNil() throws {
        let fixture = try SidebarTestFixture()
        let model = try fixture.insertProject(name: "Task", path: "/tmp/unpinned-task")
        let taskID = model.persistentModelID

        let frames = sidebarItemBoundaryFrames(
            for: .unpinnedTask(taskID),
            section: .pinned,
            geometry: [
                .pinnedTask(taskID): [CGRect(x: 0, y: 70, width: 200, height: 24)],
                .pinnedThread(taskID): [CGRect(x: 0, y: 20, width: 200, height: 24)]
            ]
        )

        XCTAssertNil(frames.header)
        XCTAssertNil(frames.terminal)
    }

    func testPinnedTaskBoundaryUsesTaskGeometryRole() throws {
        let fixture = try SidebarTestFixture()
        let model = try fixture.insertProject(name: "Task", path: "/tmp/task")
        let taskID = model.persistentModelID
        let taskFrame = CGRect(x: 0, y: 70, width: 200, height: 24)
        let threadFrame = CGRect(x: 0, y: 20, width: 200, height: 24)

        let frames = sidebarItemBoundaryFrames(
            for: .pinnedTask(taskID),
            section: .pinned,
            geometry: [
                .pinnedTask(taskID): [taskFrame],
                .pinnedThread(taskID): [threadFrame]
            ]
        )

        XCTAssertEqual(frames.header, taskFrame)
        XCTAssertEqual(frames.terminal, taskFrame)
    }
}
