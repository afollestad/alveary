import XCTest

@testable import Alveary

@MainActor
final class SidebarViewTests: XCTestCase {
    func testConfirmDeleteThreadSelectsPreviousThreadInSameProject() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        _ = makeThread(name: "Gamma", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(beta)
        appState.previousSelection = .threadId(beta.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(beta)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(alpha))
        XCTAssertEqual(appState.previousSelection, .threadId(alpha.persistentModelID))
        XCTAssertFalse(try fixture.threadExists(beta))
    }

    func testConfirmDeleteThreadSelectsNextThreadWhenNoEarlierThreadExists() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let alpha = makeThread(name: "Alpha", project: project)
        let beta = makeThread(name: "Beta", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(alpha)
        appState.previousSelection = .threadId(alpha.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(alpha)

        XCTAssertEqual(appState.selectedSidebarItem, .thread(beta))
        XCTAssertEqual(appState.previousSelection, .threadId(beta.persistentModelID))
        XCTAssertFalse(try fixture.threadExists(alpha))
    }

    func testConfirmDeleteThreadFallsBackToProjectWhenItWasLastThread() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = makeThread(name: "Alpha", project: project)
        fixture.context.insert(project)
        try fixture.context.save()

        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        appState.previousSelection = .threadId(thread.persistentModelID)

        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)
        await view.confirmDeleteThread(thread)

        XCTAssertEqual(appState.selectedSidebarItem, .project(project))
        XCTAssertEqual(appState.previousSelection, .projectPath(project.path))
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testArchiveConfirmationMessagePointsToProjectSettingsArchivedThreads() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.archiveConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This archives \"Thread\". You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
        )
    }

    func testDeleteConfirmationMessageQuotesThreadName() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )
        let appState = AppState()
        let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

        let message = view.deleteConfirmationMessage(for: thread)

        XCTAssertEqual(
            message,
            "This permanently deletes \"Thread\" and removes its worktree and branch if present."
        )
    }

    func testDeleteKeyDecisionUsesArchiveConfirmationByDefault() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        switch threadCleanupConfirmation(for: .thread(thread), action: .archive) {
        case .archive(let confirmedThread):
            XCTAssertEqual(confirmedThread.persistentModelID, thread.persistentModelID)
        default:
            XCTFail("Expected archive confirmation")
        }
    }

    func testDeleteKeyDecisionUsesDeleteConfirmationWhenConfigured() throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project"
        )

        switch threadCleanupConfirmation(for: .thread(thread), action: .delete) {
        case .delete(let confirmedThread):
            XCTAssertEqual(confirmedThread.persistentModelID, thread.persistentModelID)
        default:
            XCTFail("Expected delete confirmation")
        }
    }

    func testDeleteKeyDecisionIgnoresNonThreadSelection() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary-project")

        XCTAssertNil(threadCleanupConfirmation(for: .project(project), action: .archive))
        XCTAssertNil(threadCleanupConfirmation(for: .skills, action: .delete))
        XCTAssertNil(threadCleanupConfirmation(for: nil, action: .archive))
    }

    private func makeThread(name: String, project: Project) -> AgentThread {
        let thread = AgentThread(name: name, project: project)
        let conversation = Conversation(
            id: UUID().uuidString,
            title: "Main",
            provider: "claude",
            thread: thread
        )
        thread.conversations = [conversation]
        project.threads.append(thread)
        return thread
    }
}
