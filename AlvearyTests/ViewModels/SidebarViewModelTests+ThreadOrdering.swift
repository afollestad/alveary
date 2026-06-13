import Foundation
import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
    func testActiveThreadsSortsNewestModifiedThreadsFirstWithinProject() throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let newest = AgentThread(name: "Zulu", modifiedAt: Date(timeIntervalSince1970: 300), project: project)
        let oldest = AgentThread(name: "alpha", modifiedAt: Date(timeIntervalSince1970: 100), project: project)
        let unmodified = AgentThread(name: "Beta", modifiedAt: nil, project: project)
        let archived = AgentThread(name: "Archived", modifiedAt: Date(timeIntervalSince1970: 400), archivedAt: Date(), project: project)
        project.threads = [oldest, unmodified, newest, archived]
        fixture.context.insert(project)
        try fixture.context.save()

        let activeThreads = fixture.viewModel.activeThreads(for: project)

        XCTAssertEqual(activeThreads.map(\.persistentModelID), [
            newest.persistentModelID,
            oldest.persistentModelID,
            unmodified.persistentModelID
        ])
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
}
