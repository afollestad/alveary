import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testOnlyNewestGeometryRefreshCanUpdateActiveSession() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/project")
        let item = SidebarDragItem.project(project.persistentModelID)
        let session = SidebarDragSession(
            id: UUID(),
            item: item,
            location: CGPoint(x: 100, y: 80),
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [item],
                projectsHeaderIsSticky: true
            )
        )

        XCTAssertTrue(sidebarDragGeometryRefreshIsCurrent(
            scheduledRevision: 4,
            currentRevision: 4,
            sessionID: session.id,
            state: .active(session)
        ))
        XCTAssertFalse(sidebarDragGeometryRefreshIsCurrent(
            scheduledRevision: 3,
            currentRevision: 4,
            sessionID: session.id,
            state: .active(session)
        ))
        XCTAssertFalse(sidebarDragGeometryRefreshIsCurrent(
            scheduledRevision: 4,
            currentRevision: 4,
            sessionID: UUID(),
            state: .active(session)
        ))
        XCTAssertFalse(sidebarDragGeometryRefreshIsCurrent(
            scheduledRevision: 4,
            currentRevision: 4,
            sessionID: session.id,
            state: .idle
        ))
    }

    func testDragSessionFreezesDisplayedCandidateExactlyOnce() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/project")
        let item = SidebarDragItem.project(project.persistentModelID)
        let logicalOrder = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [item],
            projectsHeaderIsSticky: true
        )
        let firstCandidate = SidebarDropCandidate(
            target: SidebarDropTarget(section: .pinned, placement: .end),
            indicatorY: 40,
            hitFrame: CGRect(x: 0, y: 30, width: 200, height: 20),
            priority: 0
        )
        let replacementCandidate = SidebarDropCandidate(
            target: SidebarDropTarget(section: .projects, placement: .before),
            indicatorY: 80,
            hitFrame: CGRect(x: 0, y: 70, width: 200, height: 20),
            priority: 0
        )
        let session = SidebarDragSession(
            id: UUID(),
            item: item,
            location: CGPoint(x: 100, y: 40),
            logicalOrder: logicalOrder
        )
        let nilSession = SidebarDragSession(
            id: UUID(),
            item: item,
            location: CGPoint(x: 100, y: 40),
            logicalOrder: logicalOrder
        )

        session.freezeDropCandidate(firstCandidate)
        session.freezeDropCandidate(replacementCandidate)
        nilSession.freezeDropCandidate(nil)
        nilSession.freezeDropCandidate(firstCandidate)

        XCTAssertTrue(session.hasFrozenDropCandidate)
        XCTAssertEqual(session.frozenDropCandidate, firstCandidate)
        XCTAssertTrue(nilSession.hasFrozenDropCandidate)
        XCTAssertNil(nilSession.frozenDropCandidate)
    }

    func testAdjacentCollapsedProjectsShareOneEquidistantDropPosition() throws {
        let fixture = try SidebarTestFixture()
        let first = try fixture.insertProject(name: "First", path: "/tmp/first")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/second")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let firstID = first.persistentModelID
        let secondID = second.persistentModelID
        let sourceID = source.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.projects, firstID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectTerminal(.projects, firstID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectHeader(.projects, secondID): [CGRect(x: 0, y: 68, width: 200, height: 24)],
            .projectTerminal(.projects, secondID): [CGRect(x: 0, y: 68, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(firstID), .project(secondID), .project(sourceID)],
            projectsHeaderIsSticky: false
        )

        let gapCandidates = sidebarDropCandidates(
            dragging: .project(sourceID),
            geometry: geometry,
            viewport: try XCTUnwrap(geometry[.viewport]?.first),
            logicalOrder: order
        ).filter { 64 ... 68 ~= $0.indicatorY }
        let indicatorYs = Set(gapCandidates.map(\.indicatorY))
        let indicatorY = try XCTUnwrap(indicatorYs.first)

        XCTAssertEqual(indicatorYs, Set([66]))
        XCTAssertEqual(indicatorY - 64, 68 - indicatorY)
        for pointerY in [60, 66, 72] {
            let candidate = sidebarDropCandidateForLocation(
                at: CGPoint(x: 100, y: pointerY),
                dragging: .project(sourceID),
                geometry: geometry,
                logicalOrder: order
            )
            XCTAssertEqual(candidate?.indicatorY, 66)
        }
    }

    func testAdjacentExpandedProjectAndProjectShareOneEquidistantDropPosition() throws {
        let fixture = try SidebarTestFixture()
        let expanded = try fixture.insertProject(name: "Expanded", path: "/tmp/expanded")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/second")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let expandedID = expanded.persistentModelID
        let secondID = second.persistentModelID
        let sourceID = source.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.projects, expandedID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.projects, expandedID): [CGRect(x: 0, y: 100, width: 200, height: 24)],
            .projectHeader(.projects, secondID): [CGRect(x: 0, y: 128, width: 200, height: 24)],
            .projectTerminal(.projects, secondID): [CGRect(x: 0, y: 128, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(expandedID), .project(secondID), .project(sourceID)],
            projectsHeaderIsSticky: false
        )

        let gapCandidates = sidebarDropCandidates(
            dragging: .project(sourceID),
            geometry: geometry,
            viewport: try XCTUnwrap(geometry[.viewport]?.first),
            logicalOrder: order
        ).filter { 124 ... 128 ~= $0.indicatorY }
        let indicatorYs = Set(gapCandidates.map(\.indicatorY))
        let indicatorY = try XCTUnwrap(indicatorYs.first)

        XCTAssertEqual(indicatorYs, Set([126]))
        XCTAssertEqual(indicatorY - 124, 128 - indicatorY)
        for pointerY in [116, 126, 136] {
            let candidate = sidebarDropCandidateForLocation(
                at: CGPoint(x: 100, y: pointerY),
                dragging: .project(sourceID),
                geometry: geometry,
                logicalOrder: order
            )
            XCTAssertEqual(candidate?.indicatorY, 126)
        }
    }

    func testSharedProjectBoundaryKeepsNonSourceSemanticAnchor() throws {
        let fixture = try SidebarTestFixture()
        let first = try fixture.insertProject(name: "First", path: "/tmp/first")
        let second = try fixture.insertProject(name: "Second", path: "/tmp/second")
        let firstID = first.persistentModelID
        let secondID = second.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.projects, firstID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectTerminal(.projects, firstID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectHeader(.projects, secondID): [CGRect(x: 0, y: 68, width: 200, height: 24)],
            .projectTerminal(.projects, secondID): [CGRect(x: 0, y: 68, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(firstID), .project(secondID)],
            projectsHeaderIsSticky: false
        )

        let draggingFirst = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 66),
            dragging: .project(firstID),
            geometry: geometry,
            logicalOrder: order
        )
        let draggingSecond = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 66),
            dragging: .project(secondID),
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(draggingFirst?.indicatorY, 66)
        XCTAssertEqual(
            draggingFirst?.target,
            SidebarDropTarget(section: .projects, item: .project(secondID), placement: .before)
        )
        XCTAssertEqual(draggingSecond?.indicatorY, 66)
        XCTAssertEqual(
            draggingSecond?.target,
            SidebarDropTarget(section: .projects, item: .project(firstID), placement: .after)
        )
    }

    func testProjectsSectionStartAndFirstProjectShareOneDropPosition() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectHeader(.projects, targetID): [CGRect(x: 0, y: 68, width: 200, height: 24)],
            .projectTerminal(.projects, targetID): [CGRect(x: 0, y: 68, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 66),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [.project(targetID), .project(sourceID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .projects, placement: .before))
        XCTAssertEqual(candidate?.indicatorY, 66)
    }

    func testPinnedSectionEndAndLastItemShareOneDropPosition() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .projectHeader(.pinned, targetID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectTerminal(.pinned, targetID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 68, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 66),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(targetID)],
                regularProjects: [.project(sourceID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, 66)
    }

    func testProjectDragRejectsInvertedPinnedBoundaryAboveSectionStart() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 240)],
            .pinnedHeader: [CGRect(x: 0, y: 60, width: 200, height: 20)],
            .projectHeader(.pinned, targetID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.pinned, targetID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 34),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(targetID)],
                regularProjects: [.project(sourceID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertNil(candidate)
    }

    func testHiddenPinnedEndIgnoresStalePinnedHeaderAfterUnpinningLastItem() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let sourceID = source.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .pinnedHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectHeader(.projects, sourceID): [CGRect(x: 0, y: 68, width: 200, height: 24)],
            .projectTerminal(.projects, sourceID): [CGRect(x: 0, y: 68, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(sourceID)],
            projectsHeaderIsSticky: true
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 44),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )
        let pinnedTargets = sidebarDropCandidates(
            dragging: .project(sourceID),
            geometry: geometry,
            viewport: try XCTUnwrap(geometry[.viewport]?.first),
            logicalOrder: order
        )
        .filter { $0.target.section == .pinned }
        .map(\.target)

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(candidate?.indicatorY, 40)
        XCTAssertEqual(pinnedTargets, [SidebarDropTarget(section: .pinned, placement: .end)])
    }

    func testDropCandidateRetentionClearsOutsideBoundaryBand() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let offscreen = try fixture.insertProject(name: "Offscreen", path: "/tmp/offscreen")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.projects, targetID): [CGRect(x: 0, y: 40, width: 200, height: 24)],
            .projectTerminal(.projects, targetID): [CGRect(x: 0, y: 40, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(targetID), .project(offscreen.persistentModelID), .project(sourceID)],
            projectsHeaderIsSticky: false
        )
        let acquired = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 66),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )
        let retained = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 69),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order,
            retainingTarget: acquired?.target
        )
        let cleared = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 73),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order,
            retainingTarget: acquired?.target
        )

        XCTAssertEqual(acquired?.indicatorY, 64)
        XCTAssertEqual(retained?.target, acquired?.target)
        XCTAssertNil(cleared)
    }

    func testDropCandidateRejectsIndicatorBeyondMaximumDistance() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.projects, targetID): [CGRect(x: 0, y: 40, width: 200, height: 100)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 75),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [.project(targetID), .project(sourceID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertNil(candidate)
    }

    func testDropCandidateRequiresPointerInsideVerticalViewport() throws {
        let fixture = try SidebarTestFixture()
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let targetID = target.persistentModelID
        let sourceID = source.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 240)],
            .projectHeader(.projects, targetID): [CGRect(x: 0, y: 0, width: 200, height: 24)],
            .projectTerminal(.projects, targetID): [CGRect(x: 0, y: 216, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(targetID), .project(sourceID)],
            projectsHeaderIsSticky: false
        )

        let topInside = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 0),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )
        let bottomInside = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 240),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )
        let above = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: -1),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )
        let below = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 241),
            dragging: .project(sourceID),
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertNotNil(topInside)
        XCTAssertNotNil(bottomInside)
        XCTAssertNil(above)
        XCTAssertNil(below)
    }

    func testPinnedThreadDragPrefersBeforeThreadAtSharedProjectBoundary() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/project")
        let targetThreadID = try fixture.insertProject(name: "Target Thread", path: "/tmp/target-thread").persistentModelID
        let sourceThreadID = try fixture.insertProject(name: "Source Thread", path: "/tmp/source-thread").persistentModelID
        let projectID = project.persistentModelID
        let geometry = targetingBaseGeometry.merging([
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .pinnedThread(targetThreadID): [CGRect(x: 0, y: 58, width: 200, height: 24)],
            .pinnedThread(sourceThreadID): [CGRect(x: 0, y: 100, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 56),
            dragging: .pinnedThread(sourceThreadID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(projectID), .pinnedThread(targetThreadID), .pinnedThread(sourceThreadID)],
                regularProjects: [],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(
            candidate?.target,
            SidebarDropTarget(section: .pinned, item: .pinnedThread(targetThreadID), placement: .before)
        )
        XCTAssertEqual(candidate?.indicatorY, 56)
    }

    private var targetingBaseGeometry: [SidebarDragGeometryRole: [CGRect]] {
        [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 240)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .projectsHeader: [CGRect(x: 0, y: 180, width: 200, height: 24)]
        ]
    }
}
