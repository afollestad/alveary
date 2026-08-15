import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    // MARK: - Eligibility

    func testCustomSectionContainerIsOfferedToEveryEligibleTaskButItsOwnMembers() throws {
        let fixture = try SidebarTestFixture()
        let member = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-member")
        let plain = try fixture.insertThread(projectName: "Q", projectPath: "/tmp/cs-plain")
        let memberID = member.persistentModelID
        let plainID = plain.persistentModelID
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [],
            customSectionIDByTaskID: [memberID: "research"]
        )

        // A member sees every section except the one it already sits in.
        XCTAssertEqual(
            sidebarCustomSectionDropCandidates(
                dragging: .unpinnedTask(memberID),
                geometry: customSectionGeometry(sectionIDs: ["research", "reading"]),
                viewport: customSectionViewport,
                logicalOrder: order
            ).map(\.target.section),
            [.customSection("reading")]
        )
        // A plain Tasks row sees both — today it has no membership container at all.
        XCTAssertEqual(
            Set(
                sidebarCustomSectionDropCandidates(
                    dragging: .unpinnedTask(plainID),
                    geometry: customSectionGeometry(sectionIDs: ["research", "reading"]),
                    viewport: customSectionViewport,
                    logicalOrder: order
                ).map(\.target.section)
            ),
            [.customSection("research"), .customSection("reading")]
        )
    }

    /// Mirrors the `Tasks` container: a pinned Task qualifies only while it may actually unpin.
    func testPinnedTaskSeesCustomSectionsOnlyWhileUnpinnable() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-pinned")
        let taskID = task.persistentModelID

        XCTAssertTrue(
            sidebarCustomSectionDropCandidates(
                dragging: .pinnedTask(taskID),
                geometry: customSectionGeometry(sectionIDs: ["research"]),
                viewport: customSectionViewport,
                logicalOrder: SidebarDragLogicalOrder(pinnedItems: [], regularProjects: [])
            ).isEmpty
        )
        XCTAssertEqual(
            sidebarCustomSectionDropCandidates(
                dragging: .pinnedTask(taskID),
                geometry: customSectionGeometry(sectionIDs: ["research"]),
                viewport: customSectionViewport,
                logicalOrder: SidebarDragLogicalOrder(
                    pinnedItems: [],
                    regularProjects: [],
                    unpinnableTaskIDs: [taskID]
                )
            ).count,
            1
        )
    }

    /// A custom section's population is Tasks, so Project-mode and project sources see nothing —
    /// exactly the sources the `Tasks` container refuses.
    func testProjectAndProjectModeSourcesNeverSeeCustomSections() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "P", path: "/tmp/cs-project")
        let thread = try fixture.insertThread(projectName: "Q", projectPath: "/tmp/cs-thread")
        let order = SidebarDragLogicalOrder(pinnedItems: [], regularProjects: [])

        for item in [
            SidebarDragItem.project(project.persistentModelID),
            .pinnedThread(thread.persistentModelID),
            .projectThread(thread.persistentModelID),
            .section(.custom("research"))
        ] {
            XCTAssertTrue(
                sidebarCustomSectionDropCandidates(
                    dragging: item,
                    geometry: customSectionGeometry(sectionIDs: ["research"]),
                    viewport: customSectionViewport,
                    logicalOrder: order
                ).isEmpty,
                "\(item)"
            )
        }
    }

    // MARK: - Container shape

    func testCustomSectionContainerSpansHeaderThroughTerminal() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-span")
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [customSectionViewport],
            .customSectionHeader("research"): [CGRect(x: 0, y: 100, width: 200, height: 24)],
            .customSectionTerminal("research"): [CGRect(x: 0, y: 130, width: 200, height: 24)]
        ]

        let candidate = try XCTUnwrap(
            sidebarCustomSectionDropCandidates(
                dragging: .unpinnedTask(task.persistentModelID),
                geometry: geometry,
                viewport: customSectionViewport,
                logicalOrder: SidebarDragLogicalOrder(pinnedItems: [], regularProjects: [])
            ).first
        )

        XCTAssertEqual(candidate.kind, .container)
        XCTAssertEqual(candidate.target.placement, .end)
        XCTAssertEqual(
            candidate.hitFrame,
            sidebarSectionContainerFrame(
                headerFrame: CGRect(x: 0, y: 100, width: 200, height: 24),
                contentFrames: [CGRect(x: 0, y: 130, width: 200, height: 24)]
            )
        )
    }

    /// The empty placeholder publishes the terminal, so an empty section stays droppable.
    func testEmptyCustomSectionStillOffersItsContainerFromTheHeaderAlone() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-empty")
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [customSectionViewport],
            .customSectionHeader("research"): [CGRect(x: 0, y: 100, width: 200, height: 24)]
        ]

        XCTAssertEqual(
            sidebarCustomSectionDropCandidates(
                dragging: .unpinnedTask(task.persistentModelID),
                geometry: geometry,
                viewport: customSectionViewport,
                logicalOrder: SidebarDragLogicalOrder(pinnedItems: [], regularProjects: [])
            ).count,
            1
        )
    }

    // MARK: - The Tasks pull-out gate

    /// A member must be able to leave for `Tasks`; before custom sections only a project-nested
    /// Task could, so the gate had to grow the membership term.
    func testTasksContainerAcceptsACustomSectionMemberLeaving() throws {
        let fixture = try SidebarTestFixture()
        let member = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-leave")
        let memberID = member.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [customSectionViewport],
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 230, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 220),
            dragging: .unpinnedTask(memberID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [],
                customSectionIDByTaskID: [memberID: "research"]
            )
        )

        XCTAssertEqual(candidate?.target, SidebarDropTarget(section: .tasks, placement: .end))
    }

    func testTasksContainerStillRefusesATaskAlreadyRestingThere() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertThread(projectName: "P", projectPath: "/tmp/cs-resting")
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [customSectionViewport],
            .tasksHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)],
            .tasksTerminal: [CGRect(x: 0, y: 230, width: 200, height: 24)]
        ]

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 220),
            dragging: .unpinnedTask(task.persistentModelID),
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(pinnedItems: [], regularProjects: [])
        )

        XCTAssertNil(candidate)
    }
}

@MainActor
private let customSectionViewport = CGRect(x: 0, y: 0, width: 200, height: 400)

@MainActor
private func customSectionGeometry(sectionIDs: [String]) -> [SidebarDragGeometryRole: [CGRect]] {
    var geometry: [SidebarDragGeometryRole: [CGRect]] = [.viewport: [customSectionViewport]]
    for (index, sectionID) in sectionIDs.enumerated() {
        let originY = CGFloat(100 + index * 60)
        geometry[.customSectionHeader(sectionID)] = [CGRect(x: 0, y: originY, width: 200, height: 24)]
        geometry[.customSectionTerminal(sectionID)] = [
            CGRect(x: 0, y: originY + 30, width: 200, height: 24)
        ]
    }
    return geometry
}
