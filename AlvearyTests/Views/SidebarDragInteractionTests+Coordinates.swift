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
                + SidebarRowMetrics.pinnedThreadBoundarySpacing
                + SidebarProjectListMetrics.listHeaderTopPaddingCorrection
        )
        let measuredHeaderFrame = sidebarDragGeometryFrame(
            visualHeaderFrame,
            excludingTopInset: SidebarProjectListMetrics.listHeaderDragTopInsetExclusion
        )
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [measuredHeaderFrame]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: visualHeaderFrame.minY - 2),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [sourceItem],
                projectsHeaderIsSticky: true
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, visualHeaderFrame.minY)
    }

    func testHiddenPinnedBoundaryUsesVisibleTopOfNewlyStickyProjectsHeader() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceItem = SidebarDragItem.project(source.persistentModelID)
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [viewport],
            .projectsHeader: [CGRect(x: 0, y: -3.5, width: 200, height: 39.5)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 2),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [sourceItem],
                projectsHeaderIsSticky: true
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, viewport.minY)
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
                regularProjects: [sourceItem],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertNil(candidate)
    }

    func testUnplacedListSectionHeaderCopyDoesNotStretchTheProjectsHeader() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/unplaced-source")
        let sourceItem = SidebarDragItem.project(source.persistentModelID)
        let placedHeaderFrame = CGRect(x: 0, y: 169, width: 200, height: 39.5)
        // `List` publishes the section header twice; the copy it never places reports the content
        // origin. Unioning them stretched the header from y=0 down to the section it heads.
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 52, width: 200, height: 868)],
            .topLevelTerminal: [CGRect(x: 0, y: 128, width: 200, height: 24)],
            .projectsHeader: [placedHeaderFrame, CGRect(x: 0, y: 0, width: 200, height: 39.5)]
        ]
        let logicalOrder = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [sourceItem],
            projectsHeaderIsSticky: true
        )

        XCTAssertEqual(
            sidebarProjectsHeaderFrame(
                geometry: geometry,
                viewport: try XCTUnwrap(geometry[.viewport]?.sidebarUnion),
                isSticky: true
            ),
            placedHeaderFrame
        )
        // The line stays on the `Projects` divider, and the region above it stays reachable,
        // instead of collapsing onto the top-level rows at the top of the list.
        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 160),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: logicalOrder
        )
        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, placedHeaderFrame.minY)
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
