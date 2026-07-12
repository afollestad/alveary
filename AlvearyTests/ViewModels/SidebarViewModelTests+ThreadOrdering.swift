import Foundation
import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
    func testArchiveThreadRejectsDraftWithoutStartingCleanup() async throws {
        let fixture = try SidebarTestFixture()
        let draft = try fixture.insertThread(
            projectName: "Draft",
            projectPath: "/tmp/archive-draft",
            isDraft: true
        )

        do {
            try await fixture.viewModel.archiveThread(draft)
            XCTFail("Expected draft archive to be rejected")
        } catch SidebarViewModelError.threadMissing {
            // expected
        }

        XCTAssertTrue(try fixture.requireThread(draft).isDraft)
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertTrue(destroyCalls.isEmpty)
    }

    func testArchiveThreadRejectsDeletedModelTokenWithoutDereferencingIt() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Deleted",
            projectPath: "/tmp/archive-deleted-token"
        )
        fixture.context.delete(thread)
        try fixture.context.save()

        do {
            try await fixture.viewModel.archiveThread(thread)
            XCTFail("Expected deleted thread token to be rejected")
        } catch SidebarViewModelError.threadMissing {
            // expected
        }
    }

    func testDraftThreadsAreExcludedFromSidebarOrderingAndCounts() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/draft-ordering", name: "Draft Ordering")
        let draft = AgentThread(name: "Draft", isPinned: true, isDraft: true, project: project)
        project.threads = [draft]
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertTrue(fixture.viewModel.pinnedThreads().isEmpty)
        XCTAssertTrue(fixture.viewModel.activeThreads(for: project).isEmpty)
        XCTAssertFalse(fixture.viewModel.hasAnyActiveThreads(for: project))
    }

    func testPinnedThreadsFetchesUnarchivedPinnedThreadsSortedByActivity() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let newest = AgentThread(name: "Zulu", isPinned: true, modifiedAt: Date(timeIntervalSince1970: 300), project: project)
        let oldest = AgentThread(name: "alpha", isPinned: true, modifiedAt: Date(timeIntervalSince1970: 100), project: project)
        let unmodified = AgentThread(name: "Beta", isPinned: true, modifiedAt: nil, project: project)
        let unpinned = AgentThread(name: "Unpinned", modifiedAt: Date(timeIntervalSince1970: 400), project: project)
        let archived = AgentThread(
            name: "Archived",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 500),
            archivedAt: Date(),
            project: project
        )
        project.threads = [oldest, unmodified, newest, unpinned, archived]
        fixture.context.insert(project)
        try fixture.context.save()

        let pinnedThreads = fixture.viewModel.pinnedThreads()

        XCTAssertEqual(pinnedThreads.map(\.persistentModelID), [
            newest.persistentModelID,
            oldest.persistentModelID,
            unmodified.persistentModelID
        ])
    }

    func testPinnedThreadsKeepManualOrderWhenActivityChanges() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let first = AgentThread(
            name: "First",
            isPinned: true,
            pinnedSortOrder: 0,
            modifiedAt: Date(timeIntervalSince1970: 100),
            project: project
        )
        let second = AgentThread(
            name: "Second",
            isPinned: true,
            pinnedSortOrder: 1,
            modifiedAt: Date(timeIntervalSince1970: 200),
            project: project
        )
        project.threads = [first, second]
        fixture.context.insert(project)
        try fixture.context.save()

        first.modifiedAt = Date(timeIntervalSince1970: 1_000)
        second.modifiedAt = Date(timeIntervalSince1970: 2_000)
        try fixture.context.save()

        XCTAssertEqual(fixture.viewModel.pinnedThreads().map(\.persistentModelID), [
            first.persistentModelID,
            second.persistentModelID
        ])
    }

    func testPinnedThreadsExcludesChildrenOwnedByPinnedProjects() throws {
        let fixture = try SidebarTestFixture()
        let pinnedProject = Project(path: "/tmp/pinned-project", name: "Pinned Project", isPinned: true)
        let pinnedChild = AgentThread(name: "Pinned Child", isPinned: true, modifiedAt: Date(timeIntervalSince1970: 300), project: pinnedProject)
        pinnedProject.threads = [pinnedChild]
        let regularProject = Project(path: "/tmp/regular-project", name: "Regular Project")
        let standalonePinned = AgentThread(
            name: "Standalone",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 200),
            project: regularProject
        )
        regularProject.threads = [standalonePinned]
        fixture.context.insert(pinnedProject)
        fixture.context.insert(regularProject)
        try fixture.context.save()

        let pinnedThreads = fixture.viewModel.pinnedThreads()

        XCTAssertEqual(pinnedThreads.map(\.persistentModelID), [standalonePinned.persistentModelID])
    }

    func testActiveThreadsSortsNewestModifiedThreadsFirstWithinProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let newest = AgentThread(name: "Zulu", modifiedAt: Date(timeIntervalSince1970: 300), project: project)
        let oldest = AgentThread(name: "alpha", modifiedAt: Date(timeIntervalSince1970: 100), project: project)
        let unmodified = AgentThread(name: "Beta", modifiedAt: nil, project: project)
        let pinned = AgentThread(name: "Pinned", isPinned: true, modifiedAt: Date(timeIntervalSince1970: 400), project: project)
        let archived = AgentThread(name: "Archived", modifiedAt: Date(timeIntervalSince1970: 400), archivedAt: Date(), project: project)
        project.threads = [oldest, unmodified, newest, pinned, archived]
        fixture.context.insert(project)
        try fixture.context.save()

        let activeThreads = fixture.viewModel.activeThreads(for: project)

        XCTAssertEqual(activeThreads.map(\.persistentModelID), [
            newest.persistentModelID,
            oldest.persistentModelID,
            unmodified.persistentModelID
        ])
    }

    func testHasAnyActiveThreadsIncludesPinnedThreads() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let pinned = AgentThread(name: "Pinned", isPinned: true, project: project)
        let archived = AgentThread(name: "Archived", archivedAt: Date(), project: project)
        project.threads = [pinned, archived]
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertTrue(fixture.viewModel.hasAnyActiveThreads(for: project))
    }

    func testPinnedItemsMixProjectsAndStandaloneThreadsByNewestActivity() throws {
        let fixture = try SidebarTestFixture()
        let newestProject = Project(path: "/tmp/newest-project", name: "Newest Project", isPinned: true)
        let newestProjectThread = AgentThread(
            name: "Project Child",
            modifiedAt: Date(timeIntervalSince1970: 500),
            project: newestProject
        )
        newestProject.threads = [newestProjectThread]
        let regularProject = Project(path: "/tmp/regular-project", name: "Regular Project")
        let standaloneThread = AgentThread(
            name: "Standalone",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 400),
            project: regularProject
        )
        regularProject.threads = [standaloneThread]
        let olderProject = Project(path: "/tmp/older-project", name: "Older Project", isPinned: true)
        let olderProjectThread = AgentThread(
            name: "Older Child",
            modifiedAt: Date(timeIntervalSince1970: 300),
            project: olderProject
        )
        olderProject.threads = [olderProjectThread]
        fixture.context.insert(newestProject)
        fixture.context.insert(regularProject)
        fixture.context.insert(olderProject)
        try fixture.context.save()

        let pinnedItems = fixture.viewModel.pinnedItems(projects: [olderProject, regularProject, newestProject])

        XCTAssertEqual(pinnedItems.map(\.sidebarItem), [
            .project(newestProject),
            .thread(standaloneThread),
            .project(olderProject)
        ])
    }

    func testPinnedItemsFallBackToLocalizedDisplayName() throws {
        let fixture = try SidebarTestFixture()
        let betaProject = Project(path: "/tmp/beta", name: "Beta", isPinned: true)
        let alphaProject = Project(path: "/tmp/alpha", name: "alpha", isPinned: true)
        fixture.context.insert(betaProject)
        fixture.context.insert(alphaProject)
        try fixture.context.save()

        let pinnedItems = fixture.viewModel.pinnedItems(projects: [betaProject, alphaProject])

        XCTAssertEqual(pinnedItems.map(\.sidebarItem), [
            .project(alphaProject),
            .project(betaProject)
        ])
    }

    func testSetProjectPinnedPersistsStateAndClearsUnarchivedChildPins() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let pinnedChild = AgentThread(name: "Pinned", isPinned: true, project: project)
        let unpinnedChild = AgentThread(name: "Unpinned", project: project)
        let archivedPinnedChild = AgentThread(name: "Archived", isPinned: true, archivedAt: Date(), project: project)
        project.threads = [pinnedChild, unpinnedChild, archivedPinnedChild]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setProjectPinned(project, isPinned: true)

        XCTAssertTrue(project.isPinned)
        XCTAssertNil(project.sidebarSortOrder)
        XCTAssertEqual(project.pinnedSortOrder, 0)
        XCTAssertFalse(pinnedChild.isPinned)
        XCTAssertNil(pinnedChild.pinnedSortOrder)
        XCTAssertFalse(unpinnedChild.isPinned)
        XCTAssertTrue(archivedPinnedChild.isPinned)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 1)
    }

    func testSetProjectPinnedMovesFormerlyPinnedChildrenIntoNormalProjectSortOrder() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let olderPinned = AgentThread(name: "Older Pinned", isPinned: true, modifiedAt: Date(timeIntervalSince1970: 100), project: project)
        let newestUnpinned = AgentThread(name: "Newest Unpinned", modifiedAt: Date(timeIntervalSince1970: 300), project: project)
        let unmodifiedPinned = AgentThread(name: "Unmodified Pinned", isPinned: true, modifiedAt: nil, project: project)
        project.threads = [olderPinned, newestUnpinned, unmodifiedPinned]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setProjectPinned(project, isPinned: true)

        let activeThreads = fixture.viewModel.activeThreads(for: project)
        XCTAssertEqual(activeThreads.map(\.persistentModelID), [
            newestUnpinned.persistentModelID,
            olderPinned.persistentModelID,
            unmodifiedPinned.persistentModelID
        ])
    }

    func testSetProjectUnpinnedLeavesChildPinsCleared() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let pinnedChild = AgentThread(name: "Pinned", isPinned: true, project: project)
        project.threads = [pinnedChild]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setProjectPinned(project, isPinned: true)
        try fixture.viewModel.setProjectPinned(project, isPinned: false)

        XCTAssertFalse(project.isPinned)
        XCTAssertEqual(project.sidebarSortOrder, 0)
        XCTAssertNil(project.pinnedSortOrder)
        XCTAssertFalse(pinnedChild.isPinned)
        XCTAssertNil(pinnedChild.pinnedSortOrder)
        XCTAssertEqual(fixture.viewModel.activeThreads(for: project).map(\.persistentModelID), [pinnedChild.persistentModelID])
    }

    func testSetThreadPinnedPersistsStateAndRefreshesOrderVersion() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")

        try fixture.viewModel.setThreadPinned(thread, isPinned: true)

        let pinnedThread = try fixture.requireThread(thread)
        XCTAssertTrue(pinnedThread.isPinned)
        XCTAssertEqual(pinnedThread.pinnedSortOrder, 0)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 1)

        try fixture.viewModel.setThreadPinned(thread, isPinned: false)

        let unpinnedThread = try fixture.requireThread(thread)
        XCTAssertFalse(unpinnedThread.isPinned)
        XCTAssertNil(unpinnedThread.pinnedSortOrder)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 2)
    }

    func testSetThreadPinnedDoesNotPinChildOfPinnedProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary", isPinned: true)
        let thread = AgentThread(name: "Child", project: project)
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()

        try fixture.viewModel.setThreadPinned(thread, isPinned: true)

        XCTAssertFalse(thread.isPinned)
        XCTAssertEqual(fixture.viewModel.activeThreads(for: project).map(\.persistentModelID), [thread.persistentModelID])
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testArchiveThreadClearsPinnedState() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        try fixture.viewModel.setThreadPinned(thread, isPinned: true)

        try await fixture.viewModel.archiveThread(thread)

        let archivedThread = try fixture.requireThread(thread)
        XCTAssertFalse(archivedThread.isPinned)
        XCTAssertNil(archivedThread.pinnedSortOrder)
        XCTAssertNotNil(archivedThread.archivedAt)
    }

    func testArchivePinnedThreadRenumbersMixedPinnedSurvivors() async throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", isPinned: true, pinnedSortOrder: 0)
        let owner = Project(path: "/tmp/owner", name: "Owner", sidebarSortOrder: 0)
        let archived = AgentThread(name: "Archived", isPinned: true, pinnedSortOrder: 1, project: owner)
        owner.threads = [archived]
        let last = Project(path: "/tmp/last", name: "Last", isPinned: true, pinnedSortOrder: 2)
        fixture.context.insert(first)
        fixture.context.insert(owner)
        fixture.context.insert(last)
        try fixture.context.save()
        let archivedID = archived.persistentModelID
        let firstID = first.persistentModelID
        let lastID = last.persistentModelID

        try await fixture.viewModel.archiveThread(archived)

        let restoredArchived = try XCTUnwrap(fixture.context.resolveThread(id: archivedID))
        let restoredFirst = try XCTUnwrap(fixture.context.resolveProject(id: firstID))
        let restoredLast = try XCTUnwrap(fixture.context.resolveProject(id: lastID))
        XCTAssertNotNil(restoredArchived.archivedAt)
        XCTAssertFalse(restoredArchived.isPinned)
        XCTAssertNil(restoredArchived.pinnedSortOrder)
        XCTAssertEqual(restoredFirst.pinnedSortOrder, 0)
        XCTAssertEqual(restoredLast.pinnedSortOrder, 1)
    }

    func testRestoreClearsStalePinnedOrderAndRenumbersMixedPinnedSurvivors() async throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", isPinned: true, pinnedSortOrder: 0)
        let owner = Project(path: "/tmp/owner", name: "Owner", sidebarSortOrder: 0)
        let restored = AgentThread(
            name: "Restored",
            isPinned: true,
            pinnedSortOrder: 1,
            archivedAt: Date(),
            project: owner
        )
        owner.threads = [restored]
        let last = Project(path: "/tmp/last", name: "Last", isPinned: true, pinnedSortOrder: 2)
        fixture.context.insert(first)
        fixture.context.insert(owner)
        fixture.context.insert(last)
        try fixture.context.save()
        let restoredID = restored.persistentModelID
        let firstID = first.persistentModelID
        let lastID = last.persistentModelID

        try await fixture.viewModel.restoreThread(restored)

        let resolvedThread = try XCTUnwrap(fixture.context.resolveThread(id: restoredID))
        let resolvedFirst = try XCTUnwrap(fixture.context.resolveProject(id: firstID))
        let resolvedLast = try XCTUnwrap(fixture.context.resolveProject(id: lastID))
        XCTAssertNil(resolvedThread.archivedAt)
        XCTAssertFalse(resolvedThread.isPinned)
        XCTAssertNil(resolvedThread.pinnedSortOrder)
        XCTAssertEqual(resolvedFirst.pinnedSortOrder, 0)
        XCTAssertEqual(resolvedLast.pinnedSortOrder, 1)
    }

    func testThreadActivityNotificationsOnlyIncrementThreadOrderVersionWhenOrderChanges() async throws {
        let fixture = try SidebarTestFixture()
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
        XCTAssertEqual(fixture.viewModel.statusVersion, 0)

        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [ThreadActivityNotificationKey.didChangeOrder: false]
        )
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
        XCTAssertEqual(fixture.viewModel.statusVersion, 0)

        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [ThreadActivityNotificationKey.didChangeOrder: true]
        )
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 1)
        XCTAssertEqual(fixture.viewModel.statusVersion, 0)
    }

    func testBackfillThreadActivityNotificationsUseNonAnimatedRefresh() async throws {
        let fixture = try SidebarTestFixture()

        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [
                ThreadActivityNotificationKey.didChangeOrder: true,
                ThreadActivityNotificationKey.isBackfill: true
            ]
        )
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
        XCTAssertEqual(fixture.viewModel.statusVersion, 1)
    }

    func testPinnedThreadActivityNotificationDoesNotRefreshThreadOrderVersion() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        try fixture.viewModel.setThreadPinned(thread, isPinned: true)
        let initialVersion = fixture.viewModel.threadOrderVersion

        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [
                ThreadActivityNotificationKey.threadID: thread.persistentModelID,
                ThreadActivityNotificationKey.didChangeOrder: false
            ]
        )
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, initialVersion)
    }

    func testPinnedProjectChildNotificationWithoutOrderChangeDoesNotRefreshThreadOrderVersion() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary", isPinned: true)
        let thread = AgentThread(name: "Child", project: project)
        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        let initialVersion = fixture.viewModel.threadOrderVersion

        NotificationCenter.default.post(
            name: .threadActivityChanged,
            object: nil,
            userInfo: [
                ThreadActivityNotificationKey.threadID: thread.persistentModelID,
                ThreadActivityNotificationKey.didChangeOrder: false
            ]
        )
        await Task.yield()

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, initialVersion)
    }
}
