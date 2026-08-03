import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A thread can be archived without this window doing it — the `alveary_host` MCP tools, or
/// another window. The sidebar then has to route selection off a row that no longer renders.
@MainActor
extension SidebarViewTests {
    func testExternalArchiveOfTheSelectedThreadSelectsItsProject() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        let project = try XCTUnwrap(thread.project)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        try fixture.markThreadArchived(thread)

        view.handleThreadLifecycleChanged(threadLifecycleNotification(threadID: thread.persistentModelID))

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
    }

    func testExternalArchiveOfTheSelectedTaskFallsBackToTheBlankTaskComposer() throws {
        let fixture = try SidebarTestFixture()
        let task = AgentThread(name: "Nightly audit", modifiedAt: Date(), mode: .task)
        fixture.context.insert(task)
        try fixture.context.save()
        let appState = AppState()
        appState.selectedSidebarItem = .thread(task)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        try fixture.markThreadArchived(task)

        view.handleThreadLifecycleChanged(threadLifecycleNotification(threadID: task.persistentModelID))

        XCTAssertNil(appState.selectedSidebarItem)
        guard case .newThread(_, let mode)? = appState.pendingCommand else {
            return XCTFail("Expected a blank Task composer request")
        }
        XCTAssertEqual(mode, .task)
    }

    func testExternalArchiveLeavesAnUnrelatedSelectionAlone() throws {
        let fixture = try SidebarTestFixture()
        let selected = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        let other = try fixture.insertThread(projectName: "Other", projectPath: "/tmp/other-project")
        let appState = AppState()
        appState.selectedSidebarItem = .thread(selected)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        try fixture.markThreadArchived(other)

        view.handleThreadLifecycleChanged(threadLifecycleNotification(threadID: other.persistentModelID))

        XCTAssertEqual(appState.selectedSidebarItem, .thread(selected))
    }

    func testRestoreNotificationDoesNotRouteSelectionAway() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        // Restores post the same notification, and the thread is still active.
        view.handleThreadLifecycleChanged(threadLifecycleNotification(threadID: thread.persistentModelID))

        XCTAssertEqual(appState.selectedSidebarItem, .thread(thread))
    }

    private func threadLifecycleNotification(threadID: PersistentIdentifier) -> Notification {
        Notification(
            name: .threadLifecycleChanged,
            userInfo: [
                ThreadLifecycleNotificationKey.threadID: threadID,
                ThreadLifecycleNotificationKey.mode: AgentThreadMode.project.rawValue
            ]
        )
    }
}
