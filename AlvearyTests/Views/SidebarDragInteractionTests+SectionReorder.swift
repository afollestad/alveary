import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    // MARK: - Boundaries

    func testSectionDragOffersOneBoundaryPerSectionPlusAnAppendAtTheEnd() {
        let candidates = sidebarSectionReorderCandidates(
            dragging: .section(.tasks),
            geometry: sectionReorderGeometry(),
            viewport: sectionReorderViewport,
            logicalOrder: sectionReorderOrder()
        )

        XCTAssertEqual(
            candidates.map(\.target),
            [
                SidebarDropTarget(section: .sectionList, item: .section(.pinned), placement: .before),
                SidebarDropTarget(section: .sectionList, item: .section(.projects), placement: .before),
                SidebarDropTarget(section: .sectionList, item: .section(.tasks), placement: .before),
                SidebarDropTarget(section: .sectionList, placement: .end)
            ]
        )
        XCTAssertTrue(candidates.allSatisfy { $0.kind == .boundary })
    }

    /// A section is never a container and never lands inside one, so no row-domain target may
    /// answer it — most importantly not `Pinned`'s insertion boundaries, which
    /// `sidebarSourceCanHoldStandalonePin` would otherwise admit through its guard-else fallthrough.
    func testSectionDragSeesNoRowDomainTargets() {
        XCTAssertFalse(
            sidebarSourceCanHoldStandalonePin(
                .section(.tasks),
                logicalOrder: sectionReorderOrder()
            )
        )
        XCTAssertFalse(
            sidebarPinnedSectionIsContainerTarget(
                dragging: .section(.tasks),
                logicalOrder: sectionReorderOrder()
            )
        )

        var geometry = sectionReorderGeometry()
        geometry[.tasksTerminal] = [CGRect(x: 0, y: 230, width: 200, height: 24)]
        let candidates = sidebarDropCandidates(
            dragging: .section(.tasks),
            geometry: geometry,
            viewport: sectionReorderViewport,
            logicalOrder: sectionReorderOrder()
        )

        XCTAssertTrue(
            candidates.allSatisfy { $0.target.section == .sectionList },
            "\(candidates.map(\.target.section))"
        )
    }

    // MARK: - The append boundary

    /// `Projects` publishes no section terminal, so the append line used to ride its *header's*
    /// bottom edge — drawn under the word "Projects" and above every project in the section, which
    /// reads as dropping into it rather than after it.
    func testAppendBoundarySitsBelowTheLastSectionsRowsRatherThanItsHeader() throws {
        let fixture = try SidebarTestFixture()
        let layout = try trailingProjectsLayout(fixture: fixture)

        let candidates = sidebarSectionReorderCandidates(
            dragging: .section(.tasks),
            geometry: layout.geometry,
            viewport: sectionReorderViewport,
            logicalOrder: layout.logicalOrder
        )
        let append = try XCTUnwrap(candidates.first { $0.target.placement == .end })

        XCTAssertEqual(append.indicatorY, layout.lastProjectMaxY)
        XCTAssertNotEqual(append.indicatorY, layout.projectsHeaderMaxY)
    }

    /// A section dropped after everything is released in the empty area below the rows, which is
    /// past the proximity gate every other insertion line answers to.
    func testAppendBoundaryIsReachableFromTheEmptyAreaBelowTheLastSection() throws {
        let fixture = try SidebarTestFixture()
        let layout = try trailingProjectsLayout(fixture: fixture)

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: layout.lastProjectMaxY + 100),
            dragging: .section(.tasks),
            geometry: layout.geometry,
            logicalOrder: layout.logicalOrder
        )

        XCTAssertEqual(
            candidate?.target,
            SidebarDropTarget(section: .sectionList, placement: .end)
        )
        XCTAssertEqual(candidate?.indicatorY, layout.lastProjectMaxY)
    }

    /// A collapsed section unmounts its rows, and then the header genuinely is the whole section.
    func testAppendBoundaryFallsBackToTheHeaderWhenTheLastSectionRendersNoRows() throws {
        let fixture = try SidebarTestFixture()
        var layout = try trailingProjectsLayout(fixture: fixture)
        for projectID in layout.projectIDs {
            layout.geometry[.projectHeader(.projects, projectID)] = nil
            layout.geometry[.projectTerminal(.projects, projectID)] = nil
        }

        let candidates = sidebarSectionReorderCandidates(
            dragging: .section(.tasks),
            geometry: layout.geometry,
            viewport: sectionReorderViewport,
            logicalOrder: layout.logicalOrder
        )
        let append = try XCTUnwrap(candidates.first { $0.target.placement == .end })

        XCTAssertEqual(append.indicatorY, layout.projectsHeaderMaxY)
    }

    // MARK: - Anchor resolution

    func testDroppingASectionOnItsOwnNeighbouringBoundariesIsNoMove() {
        let sections = sectionReorderOrder().sections

        XCTAssertNil(
            sidebarSectionReorderAnchor(
                dragging: .section(.projects),
                target: SidebarDropTarget(section: .sectionList, item: .section(.projects), placement: .before),
                sections: sections
            )
        )
        // The boundary just below `Projects` is `Tasks`'s `.before` — also its current slot.
        XCTAssertNil(
            sidebarSectionReorderAnchor(
                dragging: .section(.projects),
                target: SidebarDropTarget(section: .sectionList, item: .section(.tasks), placement: .before),
                sections: sections
            )
        )
    }

    func testSectionReorderResolvesTheAnchorAfterRemovingTheMovedSection() {
        let sections = sectionReorderOrder().sections

        // Moving `Pinned` down to the end anchors on nothing.
        XCTAssertEqual(
            sidebarSectionReorderAnchor(
                dragging: .section(.pinned),
                target: SidebarDropTarget(section: .sectionList, placement: .end),
                sections: sections
            ),
            SidebarSectionReorderRequest(sectionID: .pinned, beforeSectionID: nil)
        )
        // Moving `Tasks` to the top anchors on `Pinned`.
        XCTAssertEqual(
            sidebarSectionReorderAnchor(
                dragging: .section(.tasks),
                target: SidebarDropTarget(section: .sectionList, item: .section(.pinned), placement: .before),
                sections: sections
            ),
            SidebarSectionReorderRequest(sectionID: .tasks, beforeSectionID: .pinned)
        )
        // Moving `Pinned` down one anchors on `Tasks`, not on `Projects` it was dropped after.
        XCTAssertEqual(
            sidebarSectionReorderAnchor(
                dragging: .section(.pinned),
                target: SidebarDropTarget(section: .sectionList, item: .section(.tasks), placement: .before),
                sections: sections
            ),
            SidebarSectionReorderRequest(sectionID: .pinned, beforeSectionID: .tasks)
        )
    }

    func testSectionReorderRejectsForeignTargetsAndSources() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "P", projectPath: "/tmp/reorder-foreign")
        let sections = sectionReorderOrder().sections

        XCTAssertNil(
            sidebarSectionReorderAnchor(
                dragging: .unpinnedTask(thread.persistentModelID),
                target: SidebarDropTarget(section: .sectionList, placement: .end),
                sections: sections
            )
        )
        XCTAssertNil(
            sidebarSectionReorderAnchor(
                dragging: .section(.tasks),
                target: SidebarDropTarget(section: .tasks, placement: .end),
                sections: sections
            )
        )
        // A section absent from the rendered order — removed mid-drag — resolves to no move.
        XCTAssertNil(
            sidebarSectionReorderAnchor(
                dragging: .section(.custom("gone")),
                target: SidebarDropTarget(section: .sectionList, item: .section(.pinned), placement: .before),
                sections: sections
            )
        )
    }

    // MARK: - The hidden-Pinned anchor follows the order

    /// The empty-`Pinned` target used to hardcode the `Projects` header. With sections
    /// reorderable, it anchors on whichever section actually follows `Pinned`.
    func testHiddenPinnedAnchorFollowsTheRenderedOrder() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [sectionReorderViewport],
            .tasksHeader: [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 140, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [],
            sectionOrder: [.pinned, .tasks, .projects]
        )

        XCTAssertEqual(
            sidebarSectionFollowingPinnedHeaderFrame(
                geometry: geometry,
                logicalOrder: order,
                projectsHeaderFrame: geometry[.projectsHeader]?.sidebarUnion
            ),
            CGRect(x: 0, y: 60, width: 200, height: 24)
        )
    }

    /// A section that renders nothing is skipped, so the anchor lands on the next one that does.
    func testHiddenPinnedAnchorSkipsSectionsWithoutAPublishedHeader() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [sectionReorderViewport],
            .projectsHeader: [CGRect(x: 0, y: 140, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [],
            sectionOrder: [.pinned, .custom("unmounted"), .projects]
        )

        XCTAssertEqual(
            sidebarSectionFollowingPinnedHeaderFrame(
                geometry: geometry,
                logicalOrder: order,
                projectsHeaderFrame: nil
            ),
            CGRect(x: 0, y: 140, width: 200, height: 24)
        )
    }

    /// `Pinned` last has nothing below to anchor on, so it publishes no end boundary at all.
    func testHiddenPinnedAnchorIsAbsentWhenPinnedSitsLast() {
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [sectionReorderViewport],
            .projectsHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)]
        ]

        XCTAssertNil(
            sidebarSectionFollowingPinnedHeaderFrame(
                geometry: geometry,
                logicalOrder: SidebarDragLogicalOrder(
                    pinnedItems: [],
                    regularProjects: [],
                    sectionOrder: [.projects, .pinned]
                ),
                projectsHeaderFrame: geometry[.projectsHeader]?.sidebarUnion
            )
        )
    }
}

@MainActor
private let sectionReorderViewport = CGRect(x: 0, y: 0, width: 200, height: 400)

@MainActor
private func sectionReorderOrder() -> SidebarDragLogicalOrder {
    SidebarDragLogicalOrder(
        pinnedItems: [],
        regularProjects: [],
        sections: [.section(.pinned), .section(.projects), .section(.tasks)],
        sectionOrder: [.pinned, .projects, .tasks]
    )
}

/// A sidebar whose last section is `Projects` — the one arrangement where the append boundary has
/// rows below the header it used to anchor on.
@MainActor
private struct TrailingProjectsLayout {
    var geometry: [SidebarDragGeometryRole: [CGRect]]
    let logicalOrder: SidebarDragLogicalOrder
    let projectIDs: [PersistentIdentifier]
    let projectsHeaderMaxY: CGFloat
    let lastProjectMaxY: CGFloat
}

@MainActor
private func trailingProjectsLayout(fixture: SidebarTestFixture) throws -> TrailingProjectsLayout {
    let first = try fixture.insertProject(name: "First", path: "/tmp/section-append-first")
    let second = try fixture.insertProject(name: "Second", path: "/tmp/section-append-second")
    let projectIDs = [first.persistentModelID, second.persistentModelID]
    var geometry: [SidebarDragGeometryRole: [CGRect]] = [
        .viewport: [sectionReorderViewport],
        .tasksHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
        .tasksTerminal: [CGRect(x: 0, y: 70, width: 200, height: 24)],
        .projectsHeader: [CGRect(x: 0, y: 130, width: 200, height: 24)]
    ]
    for (offset, projectID) in projectIDs.enumerated() {
        let frame = CGRect(x: 0, y: 160 + CGFloat(offset) * 30, width: 200, height: 24)
        geometry[.projectHeader(.projects, projectID)] = [frame]
        geometry[.projectTerminal(.projects, projectID)] = [frame]
    }

    return TrailingProjectsLayout(
        geometry: geometry,
        logicalOrder: SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: projectIDs.map { .project($0) },
            sections: [.section(.tasks), .section(.projects)],
            sectionOrder: [.tasks, .projects]
        ),
        projectIDs: projectIDs,
        projectsHeaderMaxY: 154,
        lastProjectMaxY: 214
    )
}

@MainActor
private func sectionReorderGeometry() -> [SidebarDragGeometryRole: [CGRect]] {
    [
        .viewport: [sectionReorderViewport],
        .pinnedHeader: [CGRect(x: 0, y: 40, width: 200, height: 24)],
        .projectsHeader: [CGRect(x: 0, y: 120, width: 200, height: 24)],
        .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
    ]
}
