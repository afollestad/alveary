import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarSectionCollapseTests {
    // MARK: - Traversal follows the persisted section order

    func testTraversalFollowsTheRenderedSectionOrder() {
        let project = Project(path: "/tmp/order-projects", name: "Alpha")
        let task = makeCustomSectionTask(name: "Task")

        let reordered = buildNavigableItems(
            sections: [
                SidebarSectionDescriptor(id: .tasks, name: "Tasks"),
                SidebarSectionDescriptor(id: .projects, name: "Projects")
            ],
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            activeTasks: [task]
        )

        XCTAssertEqual(reordered, [.skills, .mcp, .scheduled, .pullRequests, .thread(task), .project(project)])
    }

    func testCustomSectionThreadsTraverseInTheirSectionSlot() {
        let member = makeCustomSectionTask(name: "Member")
        let plainTask = makeCustomSectionTask(name: "Plain")

        let items = buildNavigableItems(
            sections: [
                SidebarSectionDescriptor(id: .custom("research"), name: "Research"),
                SidebarSectionDescriptor(id: .tasks, name: "Tasks")
            ],
            projects: [],
            expandedProjects: [],
            activeThreads: { _ in [] },
            activeTasks: [plainTask],
            customSectionThreads: { $0 == "research" ? [member] : [] }
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .pullRequests, .thread(member), .thread(plainTask)])
    }

    func testCollapsedCustomSectionDropsItsThreadsFromTraversal() {
        let member = makeCustomSectionTask(name: "Member")

        let collapsed = buildNavigableItems(
            sections: [SidebarSectionDescriptor(id: .custom("research"), name: "Research")],
            projects: [],
            expandedProjects: [],
            activeThreads: { _ in [] },
            customSectionThreads: { _ in [member] },
            collapsedSections: [.custom("research")]
        )

        XCTAssertEqual(collapsed, [.skills, .mcp, .scheduled, .pullRequests])
    }

    /// Collapse state is keyed by section ID, so one collapsed section never hides another's rows.
    func testCollapsingOneCustomSectionLeavesTheOthersTraversable() {
        let hidden = makeCustomSectionTask(name: "Hidden")
        let visible = makeCustomSectionTask(name: "Visible")

        let items = buildNavigableItems(
            sections: [
                SidebarSectionDescriptor(id: .custom("alpha"), name: "Alpha"),
                SidebarSectionDescriptor(id: .custom("beta"), name: "Beta")
            ],
            projects: [],
            expandedProjects: [],
            activeThreads: { _ in [] },
            customSectionThreads: { $0 == "alpha" ? [hidden] : [visible] },
            collapsedSections: [.custom("alpha")]
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .pullRequests, .thread(visible)])
    }

    // MARK: - Selection reveal

    func testSelectingACustomSectionMemberReopensThatSection() {
        let member = makeCustomSectionTask(name: "Member")

        XCTAssertEqual(
            sidebarSectionToExpand(
                for: .thread(member),
                resolveThread: { _ in member },
                resolveCustomSectionID: { _ in "research" }
            ),
            .custom("research")
        )
    }

    func testSelectingANonMemberTaskStillReopensTasks() {
        let task = makeCustomSectionTask(name: "Plain")

        XCTAssertEqual(
            sidebarSectionToExpand(
                for: .thread(task),
                resolveThread: { _ in task },
                resolveCustomSectionID: { _ in nil }
            ),
            .tasks
        )
    }

    /// A pinned member renders under `Pinned`, so nothing needs reopening even though its
    /// membership survives the pin.
    func testSelectingAPinnedCustomSectionMemberReopensNothing() {
        let pinnedMember = makeCustomSectionTask(name: "Pinned member", isPinned: true)

        XCTAssertNil(
            sidebarSectionToExpand(
                for: .thread(pinnedMember),
                resolveThread: { _ in pinnedMember },
                resolveCustomSectionID: { _ in "research" }
            )
        )
    }

    // MARK: - Collapse keys

    func testEverySectionIdentityMapsToItsCollapseKeyExceptPinned() {
        XCTAssertEqual(SidebarCollapsibleSection(sectionID: .projects), .projects)
        XCTAssertEqual(SidebarCollapsibleSection(sectionID: .tasks), .tasks)
        XCTAssertEqual(SidebarCollapsibleSection(sectionID: .custom("research")), .custom("research"))
        XCTAssertNil(SidebarCollapsibleSection(sectionID: .pinned))
    }

    // MARK: - Geometry roles

    func testEverySectionPublishesItsOwnHeaderRole() {
        XCTAssertEqual(SidebarDragGeometryRole.sectionHeader(.pinned), .pinnedHeader)
        XCTAssertEqual(SidebarDragGeometryRole.sectionHeader(.projects), .projectsHeader)
        XCTAssertEqual(SidebarDragGeometryRole.sectionHeader(.tasks), .tasksHeader)
        XCTAssertEqual(SidebarDragGeometryRole.sectionHeader(.custom("research")), .customSectionHeader("research"))
    }

    /// Only the membership containers need a terminal; `Pinned` and `Projects` expose every edge
    /// through their per-item boundaries instead.
    func testOnlyMembershipSectionsPublishATerminalRole() {
        XCTAssertEqual(SidebarDragGeometryRole.sectionTerminal(.tasks), .tasksTerminal)
        XCTAssertEqual(SidebarDragGeometryRole.sectionTerminal(.custom("research")), .customSectionTerminal("research"))
        XCTAssertNil(SidebarDragGeometryRole.sectionTerminal(.pinned))
        XCTAssertNil(SidebarDragGeometryRole.sectionTerminal(.projects))
    }

    // MARK: - Helpers

    private func makeCustomSectionTask(name: String, isPinned: Bool = false) -> AgentThread {
        AgentThread(
            name: name,
            isPinned: isPinned,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/custom-section-task-\(name)",
                ownershipStrategy: .projectLocal,
                sourceProjectPath: "/tmp/custom-section-task-\(name)"
            )
        )
    }
}
