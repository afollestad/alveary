import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    /// The drop mirrors the `Tasks` drop's outcome — unpinned, detached, activity-sorted — and
    /// adds membership, all through one `SidebarSectionService.moveThread` save.
    func testCustomSectionDropUnpinsDetachesAndSetsMembership() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)
        let project = try fixture.insertProject(name: "Home", path: "/tmp/drop-custom")
        let task = AgentThread(name: "Nested", isPinned: true, pinnedSortOrder: 0, mode: .task, project: project)
        fixture.context.insert(task)
        try fixture.context.save()

        let didMove = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .customSection(sectionID), placement: .end)
        )

        XCTAssertTrue(didMove)
        XCTAssertNil(task.project)
        XCTAssertFalse(task.isPinned)
        XCTAssertEqual(task.customSection?.id, sectionID)
    }

    func testCustomSectionDropReportsNoMoveWhenTheThreadIsAlreadyAMember() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)
        let task = makeDropTask(name: "Member", in: fixture)
        task.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        XCTAssertFalse(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .unpinnedTask(task.persistentModelID),
                target: SidebarDropTarget(section: .customSection(sectionID), placement: .end)
            )
        )
    }

    /// Only Task-shaped sources reach a custom section; the targeting layer refuses the rest, and
    /// this is the commit-side backstop.
    func testCustomSectionDropRefusesNonTaskSources() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)
        let project = try fixture.insertProject(name: "Home", path: "/tmp/drop-refuse")
        let projectThread = AgentThread(name: "Project mode", mode: .project, project: project)
        fixture.context.insert(projectThread)
        try fixture.context.save()
        let target = SidebarDropTarget(section: .customSection(sectionID), placement: .end)

        for item in [
            SidebarDragItem.project(project.persistentModelID),
            .pinnedThread(projectThread.persistentModelID),
            .projectThread(projectThread.persistentModelID)
        ] {
            XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(dragItem: item, target: target), "\(item)")
        }
    }

    /// A member dropped back on `Tasks` leaves its section, which is what makes the pull-out
    /// gate's new membership term meaningful.
    ///
    /// This has to run through `commitSidebarDrop` with a `.tasks` target — the gesture itself.
    /// Asserting `moveThreadToSection` instead is what let the drop resolve a target and commit
    /// nothing: the arm behind it detached from a project the Task did not have, and returned.
    func testTasksDropClearsCustomSectionMembership() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)
        let task = makeDropTask(name: "Member", in: fixture)
        task.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        let didMove = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .customSection(sectionID), placement: .end)
        )
        XCTAssertFalse(didMove, "already a member")

        XCTAssertTrue(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .unpinnedTask(task.persistentModelID),
                target: SidebarDropTarget(section: .tasks, placement: .end)
            )
        )
        XCTAssertNil(task.customSection)
    }

    /// The pinned arm shares the commit, so a pinned member does not unpin straight back into the
    /// section it was dragged out of.
    func testTasksDropClearsCustomSectionMembershipForAPinnedMember() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)
        let task = makeDropTask(name: "Pinned member", in: fixture)
        task.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        task.isPinned = true
        task.pinnedSortOrder = 0
        try fixture.context.save()

        XCTAssertTrue(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .pinnedTask(task.persistentModelID),
                target: SidebarDropTarget(section: .tasks, placement: .end)
            )
        )
        XCTAssertNil(task.customSection)
        XCTAssertFalse(task.isPinned)
    }

    /// The project-nested case the `Tasks` drop already handled, kept honest now that both arms
    /// share one commit: placement changes, workspace grants do not.
    func testTasksDropDetachesFromAProjectAndKeepsWorkspaceGrants() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/drop-detach")
        let task = makeDropTask(name: "Nested", in: fixture)
        task.project = project
        let grants = task.taskWorkspaceDescriptor?.grantedRoots
        try fixture.context.save()

        XCTAssertTrue(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .unpinnedTask(task.persistentModelID),
                target: SidebarDropTarget(section: .tasks, placement: .end)
            )
        )
        XCTAssertNil(task.project)
        XCTAssertEqual(task.taskWorkspaceDescriptor?.grantedRoots, grants)
    }

    // MARK: - Section reorder

    func testSectionReorderCommitsThroughTheViewModel() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try createCustomSection(named: "Research", in: fixture)

        XCTAssertTrue(try fixture.viewModel.moveSection(id: .custom(sectionID), before: .pinned))

        XCTAssertEqual(
            try fixture.viewModel.sectionService.orderedSections().map(\.id),
            [.custom(sectionID), .pinned, .projects, .tasks]
        )
    }

    /// The generic ordering path never sees a section: its own commit arm answers first, so a
    /// `.sectionList` target reaching `commitSidebarDrop` is a no-op rather than a pin mutation.
    func testSectionListTargetIsInertOnTheOrderingCommit() throws {
        let fixture = try SidebarTestFixture()

        XCTAssertFalse(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .section(.tasks),
                target: SidebarDropTarget(section: .sectionList, placement: .end)
            )
        )
    }
}

private extension SidebarViewModelTests {
    func createCustomSection(named name: String, in fixture: SidebarTestFixture) throws -> String {
        guard case .created(let descriptor) = try fixture.viewModel.createSection(name: name),
              case .custom(let id) = descriptor.id else {
            throw SidebarSectionServiceError.sectionMissing
        }
        return id
    }

    @discardableResult
    func makeDropTask(name: String, in fixture: SidebarTestFixture) -> AgentThread {
        let task = AgentThread(
            name: name,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/drop-task-\(UUID().uuidString)",
                ownershipStrategy: .projectLocal
            )
        )
        fixture.context.insert(task)
        return task
    }
}
