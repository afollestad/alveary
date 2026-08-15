import AppKit
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testEmptyPinnedTargetClaimsTheLastTopLevelRowsLowerHalf() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-source")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: sourceItem,
            geometry: hiddenPinnedGeometry(),
            logicalOrder: hiddenPinnedLogicalOrder
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.kind, .boundary)
        // Up to the top-level row's midpoint, down to the Projects header's midpoint.
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 52, width: 200, height: 47.75))
        // Only the hit region widens. The line stays on the header's top edge, where the
        // `Projects` divider is drawn.
        XCTAssertEqual(candidate?.indicatorY, 80)
    }

    func testEmptyPinnedTargetIgnoresTheIndicatorProximityGate() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-gate")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)

        // 25pt above the indicator at 80, past `maximumIndicatorDistance`, but inside the frame.
        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: sourceItem,
            geometry: hiddenPinnedGeometry(),
            logicalOrder: hiddenPinnedLogicalOrder
        )

        XCTAssertGreaterThan(abs(55 - 80), SidebarDropTargetingMetrics.maximumIndicatorDistance)
        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
    }

    func testEmptyPinnedTargetFallsBackToProjectsHeaderWithoutTopLevelGeometry() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-fallback")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        var geometry = hiddenPinnedGeometry()
        geometry[.topLevelTerminal] = nil

        let overHeader = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 95),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: hiddenPinnedLogicalOrder
        )
        let overTopLevelRows = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: hiddenPinnedLogicalOrder
        )

        XCTAssertEqual(overHeader?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(overHeader?.hitFrame, CGRect(x: 0, y: 80, width: 200, height: 19.75))
        XCTAssertEqual(overHeader?.indicatorY, 80)
        XCTAssertNil(overTopLevelRows)
    }

    func testEmptyPinnedTargetFallsBackWhenTopLevelRowsScrollAboveTheViewport() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-scrolled")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        var geometry = hiddenPinnedGeometry()
        geometry[.topLevelTerminal] = [CGRect(x: 0, y: -40, width: 200, height: 24)]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 95),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: hiddenPinnedLogicalOrder
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 80, width: 200, height: 19.75))
        XCTAssertEqual(candidate?.indicatorY, 80)
    }

    func testEmptyPinnedTargetIgnoresInvertedTopLevelGeometry() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-inverted")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        var geometry = hiddenPinnedGeometry()
        // A transient map placing the top-level group below the header it precedes.
        geometry[.topLevelTerminal] = [CGRect(x: 0, y: 150, width: 200, height: 24)]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 95),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: hiddenPinnedLogicalOrder
        )

        // The extension is dropped rather than inverting the rect; the header's own half stands.
        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 80, width: 200, height: 19.75))
        XCTAssertEqual(candidate?.indicatorY, 80)
    }

    func testEmptyPinnedTargetFollowsTheTerminalRowWhenPullRequestsIsHidden() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/hidden-pinned-no-pull-requests")
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 30),
            dragging: sourceItem,
            geometry: hiddenPullRequestsGeometry(),
            logicalOrder: hiddenPinnedLogicalOrder
        )

        // `Scheduled` now carries `.topLevelTerminal`, so the extension anchors to it and the
        // whole group sits one row higher. The target keeps the same shape.
        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.kind, .boundary)
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 24, width: 200, height: 47.75))
        XCTAssertEqual(candidate?.indicatorY, 52)
    }

    func testProjectSourceSharesTheExtendedEmptyPinnedTarget() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/hidden-pinned-project")
        let sourceItem = SidebarDragItem.project(project.persistentModelID)
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(project.persistentModelID)]
        )

        let pinnedEnd = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: sourceItem,
            geometry: hiddenPinnedGeometry(),
            logicalOrder: order
        )
        let projectsStart = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 110),
            dragging: sourceItem,
            geometry: hiddenPinnedGeometry(),
            logicalOrder: order
        )

        XCTAssertEqual(pinnedEnd?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(projectsStart?.target, SidebarDropTarget(section: .projects, placement: .before))
    }
}

/// The production empty-`Pinned` layout: top-level rows, then a sticky `Projects` section header
/// whose 39.5pt frame carries 15.5pt of internal top padding. No `Pinned` header exists, and the
/// top-level rows publish only their terminal.
private func hiddenPinnedGeometry() -> [SidebarDragGeometryRole: [CGRect]] {
    [
        .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
        .topLevelTerminal: [CGRect(x: 0, y: 40, width: 200, height: 24)],
        .projectsHeader: [CGRect(x: 0, y: 80, width: 200, height: 39.5)]
    ]
}

/// The same layout with `Pull requests` hidden: one fewer top-level row, so `Scheduled` publishes
/// the terminal and everything below it moves up by one row.
private func hiddenPullRequestsGeometry() -> [SidebarDragGeometryRole: [CGRect]] {
    [
        .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
        .topLevelTerminal: [CGRect(x: 0, y: 12, width: 200, height: 24)],
        .projectsHeader: [CGRect(x: 0, y: 52, width: 200, height: 39.5)]
    ]
}

/// `SidebarView` makes the `Projects` header sticky exactly while `Pinned` is empty.
private let hiddenPinnedLogicalOrder = SidebarDragLogicalOrder(
    pinnedItems: [],
    regularProjects: []
)
