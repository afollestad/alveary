import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testEnsureSidebarOrderingInitializedBackfillsLegacyOrderAndExcludesDrafts() throws {
        let fixture = try SidebarTestFixture()
        let zeta = Project(path: "/tmp/zeta", name: "Zeta")
        let alpha = Project(path: "/tmp/alpha", name: "Alpha")
        let pinnedProject = Project(path: "/tmp/pinned", name: "Pinned", isPinned: true)
        let pinnedProjectChild = AgentThread(
            name: "Newest Child",
            modifiedAt: Date(timeIntervalSince1970: 500),
            project: pinnedProject
        )
        pinnedProject.threads = [pinnedProjectChild]
        let regularProject = Project(path: "/tmp/regular", name: "Regular")
        let pinnedThread = AgentThread(
            name: "Pinned Thread",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 300),
            project: regularProject
        )
        let draft = AgentThread(
            name: "Draft",
            isPinned: true,
            pinnedSortOrder: 99,
            isDraft: true,
            modifiedAt: Date(timeIntervalSince1970: 900),
            project: regularProject
        )
        regularProject.threads = [pinnedThread, draft]
        fixture.context.insert(zeta)
        fixture.context.insert(alpha)
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        try fixture.context.save()

        try fixture.viewModel.ensureSidebarOrderingInitialized()

        XCTAssertEqual(alpha.sidebarSortOrder, 0)
        XCTAssertEqual(regularProject.sidebarSortOrder, 1)
        XCTAssertEqual(zeta.sidebarSortOrder, 2)
        XCTAssertNil(pinnedProject.sidebarSortOrder)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 0)
        XCTAssertEqual(pinnedThread.pinnedSortOrder, 1)
        XCTAssertTrue(draft.isPinned)
        XCTAssertNil(draft.pinnedSortOrder)
    }

    func testNormalizationKeepsManualItemsFirstThenAppendsMissingLegacyItems() throws {
        let fixture = try SidebarTestFixture()
        let manualZeta = Project(path: "/tmp/manual-zeta", name: "Zeta", sidebarSortOrder: 8)
        let manualAlpha = Project(path: "/tmp/manual-alpha", name: "Alpha", sidebarSortOrder: 8)
        let missingBeta = Project(path: "/tmp/missing-beta", name: "Beta")
        let missingCharlie = Project(path: "/tmp/missing-charlie", name: "Charlie")
        for project in [manualZeta, manualAlpha, missingBeta, missingCharlie] {
            fixture.context.insert(project)
        }
        try fixture.context.save()

        try fixture.viewModel.ensureSidebarOrderingInitialized()

        XCTAssertEqual(
            fixture.viewModel.regularProjects(from: [missingCharlie, manualZeta, missingBeta, manualAlpha]).map(\.path),
            [manualAlpha.path, manualZeta.path, missingBeta.path, missingCharlie.path]
        )
        XCTAssertEqual([manualAlpha, manualZeta, missingBeta, missingCharlie].map(\.sidebarSortOrder), [0, 1, 2, 3])
    }

    func testEnsureSidebarOrderingInitializedIsIdempotent() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project", name: "Project")
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.ensureSidebarOrderingInitialized()
        let initialVersion = fixture.viewModel.threadOrderVersion
        try fixture.viewModel.ensureSidebarOrderingInitialized()

        XCTAssertEqual(project.sidebarSortOrder, 0)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, initialVersion)
    }

    func testCommitSidebarDropMovesRegularProjectIntoPinnedOrder() throws {
        let fixture = try SidebarTestFixture()
        let pinned = Project(path: "/tmp/pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regular = Project(path: "/tmp/regular", name: "Regular", sidebarSortOrder: 0)
        fixture.context.insert(pinned)
        fixture.context.insert(regular)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(regular.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .project(pinned.persistentModelID), placement: .after)
        )

        XCTAssertTrue(didCommit)
        XCTAssertTrue(regular.isPinned)
        XCTAssertNil(regular.sidebarSortOrder)
        XCTAssertEqual(regular.pinnedSortOrder, 1)
    }

    func testCommitSidebarDropMovesPinnedProjectIntoRegularOrder() throws {
        let fixture = try SidebarTestFixture()
        let pinned = Project(path: "/tmp/pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regular = Project(path: "/tmp/regular", name: "Regular", sidebarSortOrder: 0)
        fixture.context.insert(pinned)
        fixture.context.insert(regular)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(pinned.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(regular.persistentModelID), placement: .after)
        )

        XCTAssertTrue(didCommit)
        XCTAssertFalse(pinned.isPinned)
        XCTAssertNil(pinned.pinnedSortOrder)
        XCTAssertEqual(pinned.sidebarSortOrder, 1)
    }

    func testMovingPinnedProjectIntoRegularOrderClearsStaleHiddenChildPins() throws {
        let fixture = try SidebarTestFixture()
        let pinned = Project(path: "/tmp/pinned", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let stalePinnedChild = AgentThread(name: "Stale Pin", isPinned: true, project: pinned)
        pinned.threads = [stalePinnedChild]
        let regular = Project(path: "/tmp/regular", name: "Regular", sidebarSortOrder: 0)
        fixture.context.insert(pinned)
        fixture.context.insert(regular)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(pinned.persistentModelID),
            target: SidebarDropTarget(section: .projects, item: .project(regular.persistentModelID), placement: .after)
        )

        XCTAssertTrue(didCommit)
        XCTAssertFalse(pinned.isPinned)
        XCTAssertFalse(stalePinnedChild.isPinned)
        XCTAssertNil(stalePinnedChild.pinnedSortOrder)
        XCTAssertTrue(fixture.viewModel.pinnedItems(projects: [pinned, regular]).isEmpty)
    }

    func testCommitSidebarDropReordersPinnedThreadWithinMixedPinnedItems() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/pinned-project", name: "Pinned", isPinned: true, pinnedSortOrder: 0)
        let regularProject = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 1, project: regularProject)
        regularProject.threads = [thread]
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .project(pinnedProject.persistentModelID), placement: .before)
        )

        XCTAssertTrue(didCommit)
        XCTAssertEqual(thread.pinnedSortOrder, 0)
        XCTAssertEqual(pinnedProject.pinnedSortOrder, 1)
    }

    func testProjectDropRejectsPinnedThreadAnchor() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let owner = Project(path: "/tmp/owner", name: "Owner", sidebarSortOrder: 1)
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 0, project: owner)
        owner.threads = [thread]
        fixture.context.insert(project)
        fixture.context.insert(owner)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(project.persistentModelID),
            target: SidebarDropTarget(section: .pinned, item: .pinnedThread(thread.persistentModelID), placement: .before)
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(project.isPinned)
    }

    func testPinnedThreadDropRejectsProjectsSection() throws {
        let fixture = try SidebarTestFixture()
        let owner = Project(path: "/tmp/owner", name: "Owner", sidebarSortOrder: 0)
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 0, project: owner)
        owner.threads = [thread]
        fixture.context.insert(owner)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedThread(thread.persistentModelID),
            target: SidebarDropTarget(section: .projects, placement: .end)
        )

        XCTAssertFalse(didCommit)
        XCTAssertTrue(thread.isPinned)
    }

    func testPinningProjectAbsorbsPinnedChildrenWithoutRepinningThem() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let firstChild = AgentThread(name: "First", isPinned: true, pinnedSortOrder: 0, project: project)
        let siblingProject = Project(path: "/tmp/sibling", name: "Sibling", isPinned: true, pinnedSortOrder: 1)
        let secondChild = AgentThread(name: "Second", isPinned: true, pinnedSortOrder: 2, project: project)
        project.threads = [firstChild, secondChild]
        fixture.context.insert(project)
        fixture.context.insert(siblingProject)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(project.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        XCTAssertTrue(didCommit)
        XCTAssertFalse(firstChild.isPinned)
        XCTAssertNil(firstChild.pinnedSortOrder)
        XCTAssertFalse(secondChild.isPinned)
        XCTAssertNil(secondChild.pinnedSortOrder)
        XCTAssertEqual(siblingProject.pinnedSortOrder, 0)
        XCTAssertEqual(project.pinnedSortOrder, 1)
    }

    func testContextPinAppendsProjectAfterRemovingItsPinnedChildren() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let firstChild = AgentThread(name: "First", isPinned: true, pinnedSortOrder: 0, project: project)
        let siblingProject = Project(path: "/tmp/sibling", name: "Sibling", isPinned: true, pinnedSortOrder: 1)
        let secondChild = AgentThread(name: "Second", isPinned: true, pinnedSortOrder: 2, project: project)
        project.threads = [firstChild, secondChild]
        fixture.context.insert(project)
        fixture.context.insert(siblingProject)
        try fixture.context.save()

        try fixture.viewModel.setProjectPinned(project, isPinned: true)

        XCTAssertFalse(firstChild.isPinned)
        XCTAssertFalse(secondChild.isPinned)
        XCTAssertEqual(siblingProject.pinnedSortOrder, 0)
        XCTAssertEqual(project.pinnedSortOrder, 1)
    }

    func testThreadDeletionRenumbersMixedPinnedSurvivors() throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", isPinned: true, pinnedSortOrder: 0)
        let owner = Project(path: "/tmp/owner", name: "Owner", sidebarSortOrder: 0)
        let deleted = AgentThread(name: "Deleted", isPinned: true, pinnedSortOrder: 1, project: owner)
        owner.threads = [deleted]
        let last = Project(path: "/tmp/last", name: "Last", isPinned: true, pinnedSortOrder: 2)
        fixture.context.insert(first)
        fixture.context.insert(owner)
        fixture.context.insert(last)
        try fixture.context.save()

        let deletedID = deleted.persistentModelID
        let snapshot = try fixture.viewModel.makeThreadCleanupSnapshot(deleted)
        try fixture.viewModel.commitThreadDeletion(snapshot)

        XCTAssertNil(fixture.context.resolveThread(id: deletedID))
        XCTAssertEqual(first.pinnedSortOrder, 0)
        XCTAssertEqual(last.pinnedSortOrder, 1)
    }

    func testProjectDeletionRenumbersRegularSurvivors() throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", sidebarSortOrder: 0)
        let deleted = Project(path: "/tmp/deleted", name: "Deleted", sidebarSortOrder: 1)
        let last = Project(path: "/tmp/last", name: "Last", sidebarSortOrder: 2)
        fixture.context.insert(first)
        fixture.context.insert(deleted)
        fixture.context.insert(last)
        try fixture.context.save()

        let deletedID = deleted.persistentModelID
        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(deleted)
        try fixture.viewModel.commitProjectDeletion(snapshot)

        XCTAssertNil(fixture.context.resolveProject(id: deletedID))
        XCTAssertEqual(first.sidebarSortOrder, 0)
        XCTAssertEqual(last.sidebarSortOrder, 1)
    }

    func testProjectDeletionExcludesPinnedChildrenAndRenumbersMixedPinnedSurvivors() throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", isPinned: true, pinnedSortOrder: 0)
        let deleted = Project(path: "/tmp/deleted", name: "Deleted", sidebarSortOrder: 0)
        let firstChild = AgentThread(name: "First Child", isPinned: true, pinnedSortOrder: 1, project: deleted)
        let secondChild = AgentThread(name: "Second Child", isPinned: true, pinnedSortOrder: 2, project: deleted)
        deleted.threads = [firstChild, secondChild]
        let last = Project(path: "/tmp/last", name: "Last", isPinned: true, pinnedSortOrder: 3)
        fixture.context.insert(first)
        fixture.context.insert(deleted)
        fixture.context.insert(last)
        try fixture.context.save()

        let deletedID = deleted.persistentModelID
        let firstChildID = firstChild.persistentModelID
        let secondChildID = secondChild.persistentModelID
        let snapshot = try fixture.viewModel.makeProjectDeletionSnapshot(deleted)
        try fixture.viewModel.commitProjectDeletion(snapshot)

        XCTAssertNil(fixture.context.resolveProject(id: deletedID))
        XCTAssertNil(fixture.context.resolveThread(id: firstChildID))
        XCTAssertNil(fixture.context.resolveThread(id: secondChildID))
        XCTAssertEqual(first.pinnedSortOrder, 0)
        XCTAssertEqual(last.pinnedSortOrder, 1)
    }

    func testDropSaveFailureRollsBackOrderingAndDoesNotRefreshVersion() throws {
        let fixture = try SidebarTestFixture(saveSidebarOrdering: { _ in
            throw SidebarOrderingTestError.saveFailed
        })
        let first = Project(path: "/tmp/first", name: "First", sidebarSortOrder: 0)
        let second = Project(path: "/tmp/second", name: "Second", sidebarSortOrder: 1)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .project(second.persistentModelID),
                target: SidebarDropTarget(section: .projects, item: .project(first.persistentModelID), placement: .before)
            )
        )

        let projects = try fixture.context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(fixture.viewModel.regularProjects(from: projects).map(\.path), [first.path, second.path])
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testContextProjectPinSaveFailureRollsBackParentAndChildOrdering() throws {
        let fixture = try SidebarTestFixture(saveSidebarOrdering: { _ in
            throw SidebarOrderingTestError.saveFailed
        })
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let child = AgentThread(name: "Child", isPinned: true, pinnedSortOrder: 0, project: project)
        project.threads = [child]
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.viewModel.setProjectPinned(project, isPinned: true))

        let restoredProject = try XCTUnwrap(fixture.context.resolveProject(id: project.persistentModelID))
        let restoredChild = try XCTUnwrap(fixture.context.resolveThread(id: child.persistentModelID))
        XCTAssertFalse(restoredProject.isPinned)
        XCTAssertEqual(restoredProject.sidebarSortOrder, 0)
        XCTAssertNil(restoredProject.pinnedSortOrder)
        XCTAssertTrue(restoredChild.isPinned)
        XCTAssertEqual(restoredChild.pinnedSortOrder, 0)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testContextThreadUnpinSaveFailureRollsBackOrdering() throws {
        let fixture = try SidebarTestFixture(saveSidebarOrdering: { _ in
            throw SidebarOrderingTestError.saveFailed
        })
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let thread = AgentThread(name: "Thread", isPinned: true, pinnedSortOrder: 0, project: project)
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.viewModel.setThreadPinned(thread, isPinned: false))

        let restoredThread = try XCTUnwrap(fixture.context.resolveThread(id: thread.persistentModelID))
        XCTAssertTrue(restoredThread.isPinned)
        XCTAssertEqual(restoredThread.pinnedSortOrder, 0)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testContextThreadPinPreflushFailureDoesNotMutateOrdering() throws {
        let fixture = try SidebarTestFixture(savePendingSidebarChanges: { _ in
            throw SidebarOrderingTestError.preflushFailed
        })
        let project = Project(path: "/tmp/project", name: "Project", sidebarSortOrder: 0)
        let thread = AgentThread(name: "Thread", project: project)
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        project.name = "Pending unrelated rename"

        XCTAssertThrowsError(try fixture.viewModel.setThreadPinned(thread, isPinned: true))

        XCTAssertFalse(thread.isPinned)
        XCTAssertNil(thread.pinnedSortOrder)
        XCTAssertEqual(project.name, "Pending unrelated rename")
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testPreflushFailureDoesNotStartOrderingMutation() throws {
        let fixture = try SidebarTestFixture(savePendingSidebarChanges: { _ in
            throw SidebarOrderingTestError.preflushFailed
        })
        let first = Project(path: "/tmp/first", name: "First", sidebarSortOrder: 0)
        let second = Project(path: "/tmp/second", name: "Second", sidebarSortOrder: 1)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()
        first.name = "Pending unrelated rename"

        XCTAssertThrowsError(
            try fixture.viewModel.commitSidebarDrop(
                dragItem: .project(second.persistentModelID),
                target: SidebarDropTarget(section: .projects, item: .project(first.persistentModelID), placement: .before)
            )
        )

        XCTAssertEqual(first.sidebarSortOrder, 0)
        XCTAssertEqual(second.sidebarSortOrder, 1)
        XCTAssertEqual(first.name, "Pending unrelated rename")
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }
}

private enum SidebarOrderingTestError: Error {
    case preflushFailed
    case saveFailed
}
