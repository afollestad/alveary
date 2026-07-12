import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testMonitorPointerConvertsIntoNamedViewportCoordinates() {
        let viewport = CGRect(x: 14, y: 52, width: 300, height: 600)
        let namedLocation = sidebarDragLocationInNamedSpace(
            monitorLocation: CGPoint(x: 100, y: 260),
            viewport: viewport
        )

        XCTAssertEqual(namedLocation, CGPoint(x: 114, y: 312))
        XCTAssertEqual(sidebarDragIndicatorOffset(
            indicatorY: namedLocation.y,
            viewport: viewport,
            overlayHeight: viewport.height
        ), 259)
    }

    func testConvertedMonitorPointerTargetsTheVisualBoundaryInAnOffsetViewport() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetItem = SidebarDragItem.project(target.persistentModelID)
        let sourceItem = SidebarDragItem.project(source.persistentModelID)
        let viewport = CGRect(x: 0, y: 52, width: 200, height: 240)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [viewport],
            .projectsHeader: [CGRect(x: 0, y: 52, width: 200, height: 24)],
            .projectHeader(.projects, target.persistentModelID): [CGRect(x: 0, y: 100, width: 200, height: 24)],
            .projectTerminal(.projects, target.persistentModelID): [CGRect(x: 0, y: 100, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [targetItem, sourceItem],
            projectsHeaderIsSticky: false
        )
        let monitorLocation = CGPoint(x: 100, y: 72)
        let namedLocation = sidebarDragLocationInNamedSpace(
            monitorLocation: monitorLocation,
            viewport: viewport
        )

        let convertedCandidate = sidebarDropCandidateForLocation(
            at: namedLocation,
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        let unconvertedCandidate = sidebarDropCandidateForLocation(
            at: monitorLocation,
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            convertedCandidate?.target,
            SidebarDropTarget(section: .projects, item: targetItem, placement: .after)
        )
        XCTAssertEqual(
            unconvertedCandidate?.target,
            SidebarDropTarget(section: .projects, placement: .before)
        )
    }
}
