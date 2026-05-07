import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveThreadMarksEveryConversationReadBeforeMutatingTheThread() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "P",
            projectPath: "/tmp/p-archive-multi",
            conversationIDs: ["main", "side"]
        )

        try await fixture.viewModel.archiveThread(thread)

        XCTAssertEqual(fixture.notificationManager.markReadCalls.sorted(), ["main", "side"])
    }

    func testArchiveThreadMarksReadBeforeRuntimeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "P",
            projectPath: "/tmp/p-archive-fail",
            conversationIDs: ["main"]
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.archiveThread(thread)
            XCTFail("Expected archive to throw")
        } catch {
            // expected
        }

        XCTAssertEqual(fixture.notificationManager.markReadCalls, ["main"])
    }

    func testArchiveThreadTreatsConcurrentDeletionDuringRuntimeTeardownAsSatisfied() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "P",
            projectPath: "/tmp/p-archive-delete",
            conversationIDs: ["main"]
        )
        let threadID = thread.persistentModelID

        await fixture.agentsManager.setDestroyObserver { conversationId in
            guard conversationId == "main",
                  let dbThread = fixture.context.resolveThread(id: threadID) else {
                return
            }
            fixture.context.delete(dbThread)
            try? fixture.context.save()
        }

        try await fixture.viewModel.archiveThread(thread)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(fixture.notificationManager.markReadCalls, ["main"])
    }

    func testRestoreThreadRefreshesBadgeCount() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "P", projectPath: "/tmp/p-restore")
        try fixture.markThreadArchived(thread)
        let initial = fixture.notificationManager.refreshBadgeCountCalls

        try fixture.viewModel.restoreThread(thread)

        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, initial + 1)
    }

    func testDeleteThreadMarksEveryConversationReadBeforeSwiftDataDelete() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "P",
            projectPath: "/tmp/p-delete-multi",
            conversationIDs: ["main", "side"]
        )

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(fixture.notificationManager.markReadCalls.sorted(), ["main", "side"])
    }

    func testDeleteProjectMarksEveryConversationReadAcrossAllThreads() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/p-delete-multi", name: "P")
        let first = AgentThread(name: "A", project: project)
        first.conversations = [
            Conversation(id: "a-main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: first)
        ]
        let second = AgentThread(name: "B", project: project)
        second.conversations = [
            Conversation(id: "b-main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: second),
            Conversation(id: "b-side", title: "Side", provider: "claude", isMain: false, displayOrder: 1, thread: second)
        ]
        project.threads = [first, second]
        fixture.context.insert(project)
        try fixture.context.save()

        try await fixture.viewModel.deleteProject(project)

        XCTAssertEqual(
            fixture.notificationManager.markReadCalls.sorted(),
            ["a-main", "b-main", "b-side"]
        )
    }
}
