import AppKit
import XCTest

@testable import Alveary

@MainActor
extension SidebarDragInteractionTests {
    func testTaskDragTargetsProjectGroupAndKeepsEdgeBandsForReordering() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/into-regular")
        let projectID = project.persistentModelID
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        // An expanded group: header at the top, last child row supplying the terminal frame.
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.projects, projectID): [CGRect(x: 0, y: 110, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(projectID)],
            projectsHeaderIsSticky: false
        )

        let insideGroup = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 95),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            insideGroup?.target,
            SidebarDropTarget(section: .projects, item: .project(projectID), placement: .into)
        )
        XCTAssertEqual(insideGroup?.kind, .container)
        // `Projects` publishes no insertion boundaries to a Task source, so the flat band stands
        // and no part of the group goes dead.
        XCTAssertEqual(insideGroup?.hitFrame, CGRect(x: 0, y: 66, width: 200, height: 62))
    }

    func testExpandedPinnedProjectKeepsAFullHalfRowForPinning() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-pinned-source")
        let project = try fixture.insertProject(name: "Pinned", path: "/tmp/into-pinned")
        let projectID = project.persistentModelID
        let projectItem = SidebarDragItem.project(projectID)
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            // The first pinned item takes no top spacing, so the header sits right above it.
            .pinnedHeader: [CGRect(x: 0, y: 34, width: 200, height: 20)],
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [projectItem],
            regularProjects: [],
            projectsHeaderIsSticky: false
        )

        // 8pt into a 24pt header row: inside the boundary's half-row, so it must still pin.
        let nearTopEdge = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 68),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )
        // Past the header's midpoint, where the group's child list begins.
        let insideGroup = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 76),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            nearTopEdge?.target,
            SidebarDropTarget(section: .pinned, item: projectItem, placement: .before)
        )
        XCTAssertEqual(nearTopEdge?.kind, .boundary)
        XCTAssertEqual(
            insideGroup?.target,
            SidebarDropTarget(section: .pinned, item: projectItem, placement: .into)
        )
        XCTAssertEqual(insideGroup?.kind, .container)
    }

    func testPinnedIntoTargetReservesHalfOfATallerTerminalPlaceholder() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-placeholder-source")
        let project = try fixture.insertProject(name: "Empty", path: "/tmp/into-placeholder")
        let projectID = project.persistentModelID
        let sourceItem = SidebarDragItem.unpinnedTask(sourceTask.persistentModelID)
        // An expanded pinned project whose only child row is the taller "No threads" placeholder.
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 34, width: 200, height: 20)],
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 84, width: 200, height: 30)],
            .projectsHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.project(projectID)],
            regularProjects: [],
            projectsHeaderIsSticky: false
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 85),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        // 12pt reserved from the 24pt header, 15pt from the 30pt placeholder.
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 72, width: 200, height: 27))
    }

    func testNestedTaskUnderAPinnedProjectKeepsTheFlatIntoBand() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-flat-source")
        let ownProject = try fixture.insertProject(name: "Owner", path: "/tmp/into-flat-owner")
        let project = try fixture.insertProject(name: "Other", path: "/tmp/into-flat-other")
        let projectID = project.persistentModelID
        let sourceID = sourceTask.persistentModelID
        let sourceItem = SidebarDragItem.unpinnedTask(sourceID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .pinnedHeader: [CGRect(x: 0, y: 34, width: 200, height: 20)],
            .projectHeader(.pinned, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.pinned, projectID): [CGRect(x: 0, y: 110, width: 200, height: 24)],
            .projectsHeader: [CGRect(x: 0, y: 200, width: 200, height: 24)]
        ]
        // The source sits under a pinned project, so it can hold no standalone pin and sees no
        // Pinned boundaries — nothing needs an edge band reserved for it.
        let order = SidebarDragLogicalOrder(
            pinnedItems: [.project(ownProject.persistentModelID), .project(projectID)],
            regularProjects: [],
            projectsHeaderIsSticky: false,
            projectIDByTaskID: [sourceID: ownProject.persistentModelID]
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 68),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            candidate?.target,
            SidebarDropTarget(section: .pinned, item: .project(projectID), placement: .into)
        )
        XCTAssertEqual(candidate?.hitFrame, CGRect(x: 0, y: 66, width: 200, height: 62))
    }

    func testTaskDragTargetsCollapsedProjectRow() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-collapsed-source")
        let project = try fixture.insertProject(name: "Collapsed", path: "/tmp/into-collapsed")
        let projectID = project.persistentModelID
        let sourceItem = SidebarDragItem.pinnedTask(sourceTask.persistentModelID)
        let headerFrame = CGRect(x: 0, y: 60, width: 200, height: 24)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, projectID): [headerFrame],
            .projectTerminal(.projects, projectID): [headerFrame]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(projectID)],
            projectsHeaderIsSticky: false
        )

        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 100, y: 72),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: order
        )

        XCTAssertEqual(
            candidate?.target,
            SidebarDropTarget(section: .projects, item: .project(projectID), placement: .into)
        )
    }

    func testProjectAndProjectThreadSourcesNeverTargetProjectGroups() throws {
        let fixture = try SidebarTestFixture()
        let source = try fixture.insertProject(name: "Source", path: "/tmp/into-invalid-source")
        let project = try fixture.insertProject(name: "Regular", path: "/tmp/into-invalid")
        let projectID = project.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectsHeader: [CGRect(x: 0, y: 20, width: 200, height: 24)],
            .projectHeader(.projects, projectID): [CGRect(x: 0, y: 60, width: 200, height: 24)],
            .projectTerminal(.projects, projectID): [CGRect(x: 0, y: 110, width: 200, height: 24)]
        ]
        let order = SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [.project(projectID)],
            projectsHeaderIsSticky: false
        )

        for sourceItem in [
            SidebarDragItem.project(source.persistentModelID),
            .pinnedThread(source.persistentModelID)
        ] {
            let candidates = sidebarProjectIntoDropCandidates(
                dragging: sourceItem,
                geometry: geometry,
                viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
                stickyOcclusionMaxY: nil,
                logicalOrder: order
            )
            XCTAssertTrue(candidates.isEmpty)
        }
    }

    func testStickyProjectsHeaderOcclusionTrimsIntoTargets() throws {
        let fixture = try SidebarTestFixture()
        let sourceTask = try fixture.insertProject(name: "Source", path: "/tmp/into-sticky-source")
        let project = try fixture.insertProject(name: "Occluded", path: "/tmp/into-sticky")
        let projectID = project.persistentModelID
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 200, height: 300)],
            .projectHeader(.projects, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)],
            .projectTerminal(.projects, projectID): [CGRect(x: 0, y: 30, width: 200, height: 24)]
        ]

        let occluded = sidebarProjectIntoDropCandidates(
            dragging: .unpinnedTask(sourceTask.persistentModelID),
            geometry: geometry,
            viewport: CGRect(x: 0, y: 0, width: 200, height: 300),
            stickyOcclusionMaxY: 80,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [],
                regularProjects: [.project(projectID)],
                projectsHeaderIsSticky: true
            )
        )

        XCTAssertTrue(occluded.isEmpty, "unexpected candidates: \(occluded.map(\.hitFrame))")
    }

    func testAccessDropRoutingRecognizesOnlyTaskSourcesOntoProjects() throws {
        let fixture = try SidebarTestFixture()
        let task = try fixture.insertProject(name: "Task", path: "/tmp/route-task")
        let project = try fixture.insertProject(name: "Project", path: "/tmp/route-project")
        let taskID = task.persistentModelID
        let projectID = project.persistentModelID
        let intoTarget = SidebarDropTarget(section: .projects, item: .project(projectID), placement: .into)

        XCTAssertEqual(
            sidebarTaskProjectAccessDrop(item: .unpinnedTask(taskID), target: intoTarget),
            SidebarTaskProjectAccessDrop(threadID: taskID, projectID: projectID)
        )
        XCTAssertEqual(
            sidebarTaskProjectAccessDrop(item: .pinnedTask(taskID), target: intoTarget),
            SidebarTaskProjectAccessDrop(threadID: taskID, projectID: projectID)
        )
        XCTAssertNil(sidebarTaskProjectAccessDrop(item: .project(projectID), target: intoTarget))
        XCTAssertNil(sidebarTaskProjectAccessDrop(item: .pinnedThread(taskID), target: intoTarget))
        // A reorder onto the same project must keep flowing through the ordering commit.
        XCTAssertNil(sidebarTaskProjectAccessDrop(
            item: .unpinnedTask(taskID),
            target: SidebarDropTarget(section: .projects, item: .project(projectID), placement: .before)
        ))
    }

    func testIneligibleAccessDropExplainsItselfInsteadOfOpeningTheDialog() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/into-ineligible")
        let busy = try await fixture.materializedTask(named: "Busy")
        let conversationID = try XCTUnwrap(busy.conversations.first?.id)
        await fixture.agentsManager.setStatus(.busy, for: conversationID)
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        view.requestTaskProjectAccessDrop(
            threadID: busy.persistentModelID,
            projectID: project.persistentModelID
        )

        XCTAssertNotNil(fixture.viewModel.sidebarError)
        XCTAssertEqual(try fixture.requireThread(busy.persistentModelID).mode, .task)
    }

    func testScheduledAttachedAccessDropUsesTheDedicatedAttachmentAlert() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/into-scheduled")
        let task = try await fixture.materializedTask(named: "Scheduled")
        fixture.context.insert(ScheduledTask(
            title: "Nightly sweep",
            prompt: "Continue in the task.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: task
        ))
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        view.requestTaskProjectAccessDrop(
            threadID: task.persistentModelID,
            projectID: project.persistentModelID
        )

        XCTAssertNotNil(fixture.viewModel.scheduledTaskAttachmentAlert)
        XCTAssertNil(fixture.viewModel.sidebarError)
    }

    func testMoveDialogQuotesTheTaskAndAvoidsNamingASection() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "into-copy")
        let project = try fixture.insertProject(name: "af.codes", path: projectPath)
        let task = try await fixture.materializedTask(named: "New task")

        let message = sidebarTaskProjectAccessConfirmationMessage(
            for: try fixture.viewModel.validateTaskProjectAccess(
                threadID: task.persistentModelID,
                projectID: project.persistentModelID
            )
        )

        // The emphasized runs are exactly the two names, so neither can inject formatting.
        XCTAssertEqual(message.quotedThreadName, "\"New task\"")
        XCTAssertEqual(message.projectName, "af.codes")
        XCTAssertTrue(message.leading.hasPrefix("Moves"))
        XCTAssertTrue(message.detail.contains("stays a task and keeps its own workspace"))
        XCTAssertTrue(message.detail.contains("continues where it left off"))
        // A pinned Task sits under Pinned, so the copy must never claim a specific section.
        let full = message.leading + message.quotedThreadName + message.middle
            + message.projectName + message.trailing + message.detail
        XCTAssertFalse(full.contains("under Tasks"))
        XCTAssertFalse(full.contains("Pinned"))
    }

    func testIntoTargetsAreRejectedByTheOrderingCommitPath() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Project", path: "/tmp/into-ordering")
        let task = AgentThread(name: "Task", mode: .task)
        fixture.context.insert(task)
        try fixture.context.save()
        let intoTarget = SidebarDropTarget(
            section: .projects,
            item: .project(project.persistentModelID),
            placement: .into
        )

        // Conversion is async and destructive, so it must never ride the synchronous reorder path.
        XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: intoTarget
        ))
        XCTAssertNil(sidebarOrder(
            afterMoving: .unpinnedTask(task.persistentModelID),
            to: intoTarget,
            in: SidebarDragOrder(pinnedItems: [], regularProjects: [.project(project.persistentModelID)])
        ))
        XCTAssertEqual(try fixture.requireThread(task.persistentModelID).mode, .task)
    }
}
