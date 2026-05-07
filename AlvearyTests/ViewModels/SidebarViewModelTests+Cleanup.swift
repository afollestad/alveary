import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testDeleteThreadDeletesModelBeforeReportingRuntimeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"]
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockAgentsManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .destroyFailed("main"))
        }

        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testDeleteThreadKeepsModelDeletedWhenWorktreeCleanupFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true
        )
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeFailed)
        }

        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testDeleteProjectKeepsModelDeletedWhenFinalWorktreeSweepFails() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Primary", project: project)
        thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        ]

        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        await fixture.worktreeManager.setRemoveAllError(.removeAllFailed)

        do {
            try await fixture.viewModel.deleteProject(project)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .projectDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected project delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeAllFailed)
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
    }
}
