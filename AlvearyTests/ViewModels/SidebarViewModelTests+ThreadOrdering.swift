import Foundation
import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
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

    func testSetThreadPinnedPersistsStateAndRefreshesOrderVersion() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")

        try fixture.viewModel.setThreadPinned(thread, isPinned: true)

        XCTAssertTrue(try fixture.requireThread(thread).isPinned)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 1)

        try fixture.viewModel.setThreadPinned(thread, isPinned: false)

        XCTAssertFalse(try fixture.requireThread(thread).isPinned)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 2)
    }

    func testArchiveThreadClearsPinnedState() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        try fixture.viewModel.setThreadPinned(thread, isPinned: true)

        try await fixture.viewModel.archiveThread(thread)

        let archivedThread = try fixture.requireThread(thread)
        XCTAssertFalse(archivedThread.isPinned)
        XCTAssertNotNil(archivedThread.archivedAt)
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

    func testPinnedThreadActivityNotificationRefreshesThreadOrderVersion() async throws {
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

        XCTAssertEqual(fixture.viewModel.threadOrderVersion, initialVersion + 1)
    }
}
