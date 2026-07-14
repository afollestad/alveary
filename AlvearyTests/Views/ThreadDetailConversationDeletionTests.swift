import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadDetailConversationDeletionTests: XCTestCase {
    func testSaveFailureRollsBackDeletionWithoutInvalidatingController() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversationID = fixture.conversation.persistentModelID
        let threadID = fixture.thread.persistentModelID
        fixture.thread.name = "Preserved pending edit"
        var invalidated = false

        do {
            try ThreadDetailConversationDeletion.commit(
                fixture.conversation,
                in: fixture.context,
                save: { _ in throw ThreadDetailDeletionTestError.saveFailed },
                invalidateController: { invalidated = true }
            )
            XCTFail("Expected deletion save to fail")
        } catch ThreadDetailDeletionTestError.saveFailed {
            // expected
        }

        XCTAssertFalse(invalidated)
        XCTAssertNotNil(fixture.context.resolveConversation(id: conversationID))
        let verificationContext = ModelContext(fixture.container)
        XCTAssertEqual(
            verificationContext.resolveThread(id: threadID)?.name,
            "Preserved pending edit"
        )
    }

    func testActiveScheduledTaskMainConversationCannotBeRemovedFromStaleConfirmation() throws {
        try assertScheduledTaskMainConversationCannotBeRemoved(status: .running)
    }

    func testTerminalScheduledTaskMainConversationCannotBeRemovedFromStaleConfirmation() throws {
        try assertScheduledTaskMainConversationCannotBeRemoved(status: .success)
    }

    func testScheduledTaskMainConversationCloseShortcutIsConsumedWithoutRemoval() throws {
        let fixture = try scheduledTaskFixture(status: .running)
        let conversations = try fixture.context.fetch(FetchDescriptor<Conversation>())
        var removedConversationIDs: [String] = []
        let sink = ConversationCloseShortcutSink(
            conversations: conversations,
            selectedConversation: fixture.conversation,
            isRenaming: false,
            canRemove: ThreadDetailConversationDeletion.canRemove,
            onRemove: { removedConversationIDs.append($0.id) }
        )

        sink.handleShortcut()

        XCTAssertTrue(removedConversationIDs.isEmpty)
    }

    func testHostedCloseShortcutConsumesScheduledMainWithoutClosingWindow() throws {
        let fixture = try scheduledTaskFixture(status: .running)
        let conversations = try fixture.context.fetch(FetchDescriptor<Conversation>())
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: conversations,
            selectedConversation: fixture.conversation,
            isRenaming: false,
            canRemove: ThreadDetailConversationDeletion.canRemove
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    private func assertScheduledTaskMainConversationCannotBeRemoved(
        status: ScheduledTaskRunStatus
    ) throws {
        let fixture = try scheduledTaskFixture(status: status)
        let mainConversationID = fixture.conversation.persistentModelID
        var invalidated = false

        XCTAssertFalse(ThreadDetailConversationDeletion.canRemove(fixture.conversation))
        XCTAssertThrowsError(
            try ThreadDetailConversationDeletion.commit(
                fixture.conversation,
                in: fixture.context,
                invalidateController: { invalidated = true }
            )
        ) { error in
            XCTAssertEqual(
                error as? ThreadDetailConversationDeletionError,
                .scheduledTaskMainConversationRequired
            )
        }

        XCTAssertFalse(invalidated)
        XCTAssertNotNil(fixture.context.resolveConversation(id: mainConversationID))
        XCTAssertFalse(fixture.context.hasChanges)
    }

    private func scheduledTaskFixture(
        status: ScheduledTaskRunStatus
    ) throws -> ConversationViewModelTestFixture {
        let fixture = try ConversationViewModelTestFixture()
        fixture.thread.mode = .task
        let run = ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "conversation-deletion-\(UUID().uuidString)",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: status,
            titleSnapshot: "Scheduled task",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree,
            thread: fixture.thread
        )
        fixture.thread.scheduledTaskRun = run
        let sideConversation = Conversation(
            id: "scheduled-side-\(UUID().uuidString)",
            provider: "codex",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        fixture.context.insert(run)
        fixture.context.insert(sideConversation)
        try fixture.context.save()
        XCTAssertTrue(ThreadDetailConversationDeletion.canRemove(sideConversation))
        return fixture
    }
}

private enum ThreadDetailDeletionTestError: Error {
    case saveFailed
}
