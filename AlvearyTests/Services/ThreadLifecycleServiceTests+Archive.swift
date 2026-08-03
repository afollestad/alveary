import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadLifecycleServiceTests {
    func testArchiveThreadCommitsAndTearsDownEveryConversation() async throws {
        var invalidatedConversationIDs: [String] = []
        let fixture = try SidebarTestFixture(
            invalidateConversationController: { invalidatedConversationIDs.append($0) }
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main", "side"]
        )
        let dbThread = try fixture.requireThread(thread)
        dbThread.isPinned = true
        dbThread.pinnedSortOrder = 0
        try fixture.context.save()

        let diagnostics = try await fixture.viewModel.threadLifecycle.archiveThread(
            threadID: thread.persistentModelID
        )

        let archivedThread = try fixture.requireThread(thread)
        XCTAssertNotNil(archivedThread.archivedAt)
        XCTAssertFalse(archivedThread.isPinned)
        XCTAssertNil(archivedThread.pinnedSortOrder)
        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertEqual(invalidatedConversationIDs.sorted(), ["main", "side"])
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls.sorted(), ["main", "side"])
        let actions = await fixture.providerSessionActions.actions
        XCTAssertTrue(actions.contains { if case .archive = $0 { return true } else { return false } })
    }

    func testArchiveThreadReturnsProviderSessionDiagnostics() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .archive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")

        let diagnostics = try await fixture.viewModel.threadLifecycle.archiveThread(
            threadID: thread.persistentModelID
        )

        XCTAssertEqual(diagnostics.map(\.message), [diagnostic.message])
    }

    func testArchiveThreadCarriesDiagnosticsOnTheCleanupFailurePath() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .archive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"]
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            _ = try await fixture.viewModel.threadLifecycle.archiveThread(threadID: thread.persistentModelID)
            XCTFail("Expected archive to throw")
        } catch let error as ThreadArchiveCleanupError {
            // The thread is archived either way, so a caller that only presents on success
            // would drop these.
            XCTAssertEqual(error.diagnostics.map(\.message), [diagnostic.message])
            XCTAssertEqual(error.underlying as? SidebarMockAgentsManager.MockError, .destroyFailed("main"))
        }

        XCTAssertNotNil(try fixture.requireThread(thread).archivedAt)
    }

    func testArchiveThreadRunsPersistenceCommitAfterTheThreadIsArchived() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        var archivedAtCommit: Bool?

        _ = try await fixture.viewModel.threadLifecycle.archiveThread(
            threadID: thread.persistentModelID,
            onPersistenceCommit: {
                archivedAtCommit = fixture.context.resolveThread(id: thread.persistentModelID)?.archivedAt != nil
            }
        )

        XCTAssertEqual(archivedAtCommit, true)
    }

    func testArchiveThreadPostsTheLifecycleNotification() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        let threadID = thread.persistentModelID
        let posted = XCTNSNotificationExpectation(name: .threadLifecycleChanged)
        posted.handler = { notification in
            notification.userInfo?[ThreadLifecycleNotificationKey.threadID] as? PersistentIdentifier == threadID
                && notification.userInfo?[ThreadLifecycleNotificationKey.mode] as? String == AgentThreadMode.project.rawValue
        }

        _ = try await fixture.viewModel.threadLifecycle.archiveThread(threadID: threadID)

        await fulfillment(of: [posted], timeout: 1)
    }

    func testArchiveThreadRejectsDraftsAndMissingThreads() async throws {
        let fixture = try SidebarTestFixture()
        let draft = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["draft"],
            isDraft: true
        )

        await assertArchiveThrows(.threadMissing, fixture: fixture, threadID: draft.persistentModelID)

        let missingThread = AgentThread(name: "Detached")
        await assertArchiveThrows(.threadMissing, fixture: fixture, threadID: missingThread.persistentModelID)
    }

    func testArchiveThreadRejectsAScheduledTaskAttachment() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(projectName: "Alveary", projectPath: "/tmp/alveary-project")
        let dbThread = try fixture.requireThread(thread)
        let definition = ScheduledTask(
            title: "Nightly sweep",
            prompt: "Sweep the release branch.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            targetThread: dbThread
        )
        dbThread.targetedScheduledTasks = [definition]
        fixture.context.insert(definition)
        try fixture.context.save()

        await assertArchiveThrows(
            .scheduledTaskAttachment("Nightly sweep"),
            fixture: fixture,
            threadID: thread.persistentModelID
        )
        XCTAssertNil(try fixture.requireThread(thread).archivedAt)
    }

    private func assertArchiveThrows(
        _ expected: SidebarViewModelError,
        fixture: SidebarTestFixture,
        threadID: PersistentIdentifier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await fixture.viewModel.threadLifecycle.archiveThread(threadID: threadID)
            XCTFail("Expected archive to throw", file: file, line: line)
        } catch let error as SidebarViewModelError {
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
