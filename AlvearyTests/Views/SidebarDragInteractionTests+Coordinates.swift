import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testInlineHeaderGeometryPublishesOnlyItsVisibleContentRow() {
        // A 47pt header: 23pt of divider breathing room above a 24pt title row.
        let frame = CGRect(x: 12, y: 40, width: 280, height: 47)

        // `Pinned` and `Tasks` both border their section, so both hug the title rather than
        // starting up in the padding.
        XCTAssertEqual(
            sidebarDragGeometryFrame(
                frame,
                excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
            ),
            CGRect(x: 12, y: 63, width: 280, height: 24)
        )
    }

    func testHiddenPinnedDividerBoundaryRemainsAcquirableAboveProjectsHeader() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceItem = SidebarDragItem.project(source.persistentModelID)
        let visualHeaderFrame = CGRect(
            x: 0,
            y: 40,
            width: 200,
            height: SidebarRowMetrics.topLevelAndThreadContentHeight
                + SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
        )
        let measuredHeaderFrame = sidebarDragGeometryFrame(
            visualHeaderFrame,
            excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
        )
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [measuredHeaderFrame]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: measuredHeaderFrame.minY - 2),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [sourceItem]
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, measuredHeaderFrame.minY)
    }

    func testInlineProjectsHeaderDoesNotClampOffscreenBoundaryToViewport() throws {
        let fixture = try SidebarTestFixture()
        let pinned = try fixture.insertProject(name: "Pinned", path: "/tmp/pinned")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceItem = SidebarDragItem.project(source.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [CGRect(x: 0, y: -3.5, width: 200, height: 39.5)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 2),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(pinned.persistentModelID)],
                regularProjects: [sourceItem]
            )
        )

        XCTAssertNil(candidate)
    }

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
            regularProjects: [targetItem, sourceItem]
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
