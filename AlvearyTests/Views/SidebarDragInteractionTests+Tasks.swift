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

    func testUnpinnedTaskDragTargetsPinnedBoundariesWithoutExposingProjects() throws {
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
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
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

        XCTAssertEqual(tasksCandidate?.target, SidebarDropTarget(section: .tasks, placement: .end))
        XCTAssertEqual(tasksCandidate?.indicatorY, 224)
        XCTAssertNil(attachedCandidate)
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
