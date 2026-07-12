import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarDragInteractionTests: XCTestCase {
    func testIndicatorStaysFullyInsideStickyViewportEdges() {
        let viewport = CGRect(x: 0, y: 40, width: 200, height: 200)

        XCTAssertEqual(sidebarDragIndicatorOffset(indicatorY: viewport.minY, viewport: viewport, overlayHeight: 200), 0)
        XCTAssertEqual(sidebarDragIndicatorOffset(indicatorY: viewport.maxY, viewport: viewport, overlayHeight: 200), 198)
    }

    func testDragStateStartsOnceAndEscapeLatchesUntilMouseUp() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/project")
        let item = SidebarDragItem.project(project.persistentModelID)
        let sessionID = UUID()
        let logicalOrder = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [item],
            projectsHeaderIsSticky: true
        )
        var state = sidebarDragStateAfterPointerChange(
            .idle,
            item: item,
            location: CGPoint(x: 100, y: 100),
            logicalOrder: logicalOrder,
            newSessionID: sessionID
        )

        guard case .active(let session) = state else {
            return XCTFail("Expected an active drag")
        }
        XCTAssertTrue(sidebarDragTransitionStartsSession(previousState: .idle, nextState: state))
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.logicalOrder, logicalOrder)
        XCTAssertFalse(session.hasMonitorPointerLocation)

        state = sidebarDragStateAfterPointerChange(
            state,
            item: item,
            location: CGPoint(x: 100, y: 140),
            logicalOrder: logicalOrder,
            newSessionID: UUID()
        )
        guard case .active(let sourceUpdatedSession) = state else {
            return XCTFail("Expected the drag to remain active")
        }
        XCTAssertEqual(sourceUpdatedSession.location, CGPoint(x: 100, y: 100))

        sourceUpdatedSession.updateMonitorPointerLocation(CGPoint(x: 100, y: 220))
        XCTAssertTrue(sourceUpdatedSession.hasMonitorPointerLocation)
        XCTAssertEqual(sourceUpdatedSession.location, CGPoint(x: 100, y: 220))

        state = sidebarDragStateAfterEscape(state)
        XCTAssertEqual(state, .cancelledUntilMouseUp(sessionID))

        state = sidebarDragStateAfterPointerChange(
            state,
            item: item,
            location: CGPoint(x: 100, y: 140),
            logicalOrder: logicalOrder,
            newSessionID: UUID()
        )
        XCTAssertEqual(state, .cancelledUntilMouseUp(sessionID))
        XCTAssertEqual(sidebarDragStateAfterCancelledMouseUp(state), .idle)
    }

    func testFinalizationTransitionConsumesActiveSessionAtMostOnce() throws {
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
        let firstTransition = sidebarDragFinalizationTransition(
            state: .active(session),
            sessionID: session.id
        )
        let duplicateTransition = sidebarDragFinalizationTransition(
            state: firstTransition.nextState,
            sessionID: session.id
        )

        XCTAssertEqual(firstTransition.session, session)
        XCTAssertEqual(firstTransition.nextState, .idle)
        XCTAssertNil(duplicateTransition.session)
        XCTAssertEqual(duplicateTransition.nextState, .idle)
    }

    func testProjectDragDoesNotExposeBoundaryBetweenConsecutivePinnedThreads() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let firstThreadID = try fixture.insertProject(name: "Thread A", path: "/tmp/thread-a").persistentModelID
        let secondThreadID = try fixture.insertProject(name: "Thread B", path: "/tmp/thread-b").persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 90).merging([
            .pinnedThread(firstThreadID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .pinnedThread(secondThreadID): [CGRect(x: 0, y: 56, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.pinnedThread(firstThreadID), .pinnedThread(secondThreadID)],
                regularProjects: [.project(source.persistentModelID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertNil(candidate)
    }

    func testProjectDragUsesProjectAnchorAtProjectThreadBoundary() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let pinnedProject = try fixture.insertProject(name: "Pinned", path: "/tmp/pinned")
        let threadID = try fixture.insertProject(name: "Thread", path: "/tmp/thread").persistentModelID
        let projectID = pinnedProject.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 90).merging([
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .pinnedThread(threadID): [CGRect(x: 0, y: 56, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 55),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(projectID), .pinnedThread(threadID)],
                regularProjects: [.project(source.persistentModelID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, item: .project(projectID), placement: .after))
        XCTAssertEqual(candidate?.indicatorY, 55)
    }

    func testHiddenPinnedProjectsHeaderHalvesExposePinnedEndAndRegularStart() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(source.persistentModelID)],
            projectsHeaderIsSticky: true
        )

        let pinnedEnd = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 44),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )
        let regularStart = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 60),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(pinnedEnd?.target, SidebarDropTarget(section: .pinned, placement: .end))
        XCTAssertEqual(regularStart?.target, SidebarDropTarget(section: .projects, placement: .before))
    }

    func testStickyProjectsHeaderTakesPriorityOverOccludedRegularRow() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let target = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let targetID = target.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 200)],
            .projectsHeader: [CGRect(x: 0, y: 0, width: 200, height: 24)],
            .projectHeader(.projects, targetID): [CGRect(x: 0, y: 8, width: 200, height: 24)],
            .projectTerminal(.projects, targetID): [CGRect(x: 0, y: 8, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 18),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [.project(targetID), .project(source.persistentModelID)],
                projectsHeaderIsSticky: true
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .projects, placement: .before))
    }

    func testLastVisibleProjectIsNotTreatedAsLogicalSectionEnd() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let visible = try fixture.insertProject(name: "Visible", path: "/tmp/visible")
        let offscreen = try fixture.insertProject(name: "Offscreen", path: "/tmp/offscreen")
        let visibleID = visible.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 20).merging([
            .projectHeader(.projects, visibleID): [CGRect(x: 0, y: 52, width: 200, height: 24)],
            .projectTerminal(.projects, visibleID): [CGRect(x: 0, y: 52, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 72),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [
                    .project(visibleID),
                    .project(offscreen.persistentModelID),
                    .project(source.persistentModelID)
                ],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(
            section: .projects,
            item: .project(visibleID),
            placement: .after
        ))
    }

    func testExpandedProjectOnlyActivatesNearOuterBoundaries() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let expanded = try fixture.insertProject(name: "Expanded", path: "/tmp/expanded")
        let trailingID = try fixture.insertProject(name: "Trailing", path: "/tmp/trailing").persistentModelID
        let expandedID = expanded.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 180).merging([
            .projectHeader(.pinned, expandedID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.pinned, expandedID): [CGRect(x: 0, y: 100, width: 200, height: 24)],
            .pinnedThread(trailingID): [CGRect(x: 0, y: 126, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.project(expandedID), .pinnedThread(trailingID)],
            regularProjects: [.project(source.persistentModelID)],
            projectsHeaderIsSticky: false
        )

        let nearHeader = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 40),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )
        let upperInterior = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 65),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )
        let lowerInterior = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 90),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )
        let nearTerminal = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 114),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(nearHeader?.target, SidebarDropTarget(section: .pinned, item: .project(expandedID), placement: .before))
        XCTAssertNil(upperInterior)
        XCTAssertNil(lowerInterior)
        XCTAssertEqual(nearTerminal?.target, SidebarDropTarget(section: .pinned, item: .project(expandedID), placement: .after))
    }

    func testPartiallyVirtualizedProjectDoesNotInferMissingOuterBoundary() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/source")
        let expanded = try fixture.insertProject(name: "Expanded", path: "/tmp/expanded")
        let expandedID = expanded.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 180)

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 80),
            dragging: .project(source.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(expandedID)],
                regularProjects: [.project(source.persistentModelID)],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertNil(candidate)
    }

    func testPinnedThreadDragCanTargetVirtualizedProjectVisibleHeader() throws {
        let fixture = try SidebarTestFixture()
        let targetProject = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let sourceThreadID = try fixture.insertProject(name: "Source", path: "/tmp/source").persistentModelID
        let targetID = targetProject.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 220).merging([
            .projectHeader(.pinned, targetID): [CGRect(x: 0, y: 48, width: 200, height: 24)],
            .pinnedThread(sourceThreadID): [CGRect(x: 0, y: 190, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 52),
            dragging: .pinnedThread(sourceThreadID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(targetID), .pinnedThread(sourceThreadID)],
                regularProjects: [],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, item: .project(targetID), placement: .before))
    }

    func testPinnedThreadDragCanTargetVirtualizedProjectVisibleTerminal() throws {
        let fixture = try SidebarTestFixture()
        let targetProject = try fixture.insertProject(name: "Target", path: "/tmp/target")
        let sourceThreadID = try fixture.insertProject(name: "Source", path: "/tmp/source").persistentModelID
        let targetID = targetProject.persistentModelID
        let geometry = baseGeometry(projectsHeaderY: 220).merging([
            .projectTerminal(.pinned, targetID): [CGRect(x: 0, y: 160, width: 200, height: 24)],
            .pinnedThread(sourceThreadID): [CGRect(x: 0, y: 190, width: 200, height: 24)]
        ], uniquingKeysWith: { _, rhs in rhs })

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 178),
            dragging: .pinnedThread(sourceThreadID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [.project(targetID), .pinnedThread(sourceThreadID)],
                regularProjects: [],
                projectsHeaderIsSticky: false
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .pinned, item: .project(targetID), placement: .after))
    }

    private func baseGeometry(projectsHeaderY: CGFloat) -> [SidebarDragGeometryRole: [CGRect]] {
        [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 240)],
            .pinnedHeader: [CGRect(x: 0, y: 6, width: 200, height: 20)],
            .projectsHeader: [CGRect(x: 0, y: projectsHeaderY, width: 200, height: 24)]
        ]
    }
}
