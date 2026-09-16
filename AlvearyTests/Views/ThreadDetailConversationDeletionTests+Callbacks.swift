import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ThreadDetailConversationDeletionTests {
    func testSecondaryCallbackRemovalPausesOnlyItsSchedulesAndRollsBackAtomically() throws {
        let fixture = try ConversationViewModelTestFixture()
        let secondary = Conversation(harness: "codex", isMain: false, thread: fixture.thread)
        fixture.context.insert(secondary)
        let callback = ScheduledTask(
            title: "Callback", prompt: "Hello", destination: .existingThread, recurrence: .once(.distantFuture),
            timeZoneIdentifier: "UTC", harnessID: "codex", nextOccurrenceAt: .distantFuture, targetThread: fixture.thread
        )
        callback.exactTargetConversationID = secondary.id
        let mainSchedule = ScheduledTask(
            title: "Main", prompt: "Main", destination: .existingThread, recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "UTC", harnessID: "codex", targetThread: fixture.thread
        )
        fixture.context.insert(callback)
        fixture.context.insert(mainSchedule)
        try fixture.context.save()
        let id = secondary.id
        XCTAssertTrue(ThreadDetailConversationDeletion.canRemove(secondary))
        XCTAssertThrowsError(try ThreadDetailConversationDeletion.commit(
            secondary, in: fixture.context, save: { _ in throw NSError(domain: "save", code: 1) }, invalidateController: {}
        ))
        XCTAssertNotNil(fixture.context.resolveConversation(conversationID: id))
        XCTAssertEqual(callback.state, .active)
        XCTAssertEqual(callback.nextOccurrenceAt, .distantFuture)
        try ThreadDetailConversationDeletion.commit(secondary, in: fixture.context, invalidateController: {})
        XCTAssertNil(fixture.context.resolveConversation(conversationID: id))
        XCTAssertEqual(callback.state, .paused)
        XCTAssertEqual(callback.exactTargetConversationID, id)
        XCTAssertNil(callback.nextOccurrenceAt)
        XCTAssertEqual(mainSchedule.state, .active)
        let mutations = ScheduledTaskMutationService(modelContext: fixture.context)
        XCTAssertThrowsError(try mutations.resume(definitionID: callback.id))
        XCTAssertThrowsError(try mutations.prepareRunNow(definitionID: callback.id))
    }

    func testActiveExactCallbackMustFinishBeforeConversationDeletionCommits() throws {
        let fixture = try ConversationViewModelTestFixture()
        let run = ScheduledTaskRun(
            occurrenceID: "callback", definitionID: "deleted-definition", definitionRevision: 1, occurrenceAt: .now,
            triggerKind: .scheduled, status: .running, titleSnapshot: "Callback", promptSnapshot: "Hello",
            destinationSnapshot: .existingThread, targetConversationIDSnapshot: fixture.conversation.id,
            timeZoneIdentifierSnapshot: "UTC", harnessIDSnapshot: "codex", effortSnapshot: "medium",
            permissionModeSnapshot: "default", workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree, targetThread: fixture.thread
        )
        run.isExactTargetSnapshot = true
        fixture.context.insert(run)
        try fixture.context.save()
        XCTAssertTrue(ThreadDetailConversationDeletion.canRemove(fixture.conversation))
        XCTAssertThrowsError(try ThreadDetailConversationDeletion.commit(fixture.conversation, in: fixture.context, invalidateController: {}))
        run.status = .interrupted
        run.requiresFinalizationRecovery = true
        XCTAssertThrowsError(try ThreadDetailConversationDeletion.requireQuiescent(fixture.conversation))
        run.requiresFinalizationRecovery = false
        XCTAssertNoThrow(try ThreadDetailConversationDeletion.requireQuiescent(fixture.conversation))
    }
}
