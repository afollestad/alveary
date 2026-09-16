import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testOneOffSecondaryCallbackWaitsThenClaimsOnceWithItsOwnHarness() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(path: "/tmp/callback-project", name: "Callback")
        let thread = AgentThread(name: "Caller", project: project)
        let main = Conversation(harness: "claude", thread: thread)
        let secondary = Conversation(harness: "codex", isMain: false, displayOrder: 1, thread: thread)
        thread.conversations = [main, secondary]
        project.threads = [thread]
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(recurrence: .once(fixture.date(300)), nextOccurrenceAt: fixture.date(300))
        definition.destination = .existingThread
        definition.targetThread = thread
        definition.exactTargetConversationID = secondary.id
        try fixture.context.save()
        let readiness = CallbackTargetReadiness()
        let engine = fixture.makeEngine(targetIsReady: { id in
            XCTAssertEqual(id, secondary.id)
            return readiness.ready
        })
        let waiting = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301))
        guard case .waitingForTarget = waiting else { return XCTFail("Expected busy callback to wait") }
        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.date(300))
        XCTAssertEqual(definition.state, .active)
        readiness.ready = true
        let claim = try await engine.claimDue(definitionID: definition.id, at: fixture.date(302))
        guard case .claimed(let id) = claim else { return XCTFail("Expected a callback claim") }
        let run = try XCTUnwrap(fixture.run(id: id))
        XCTAssertEqual(run.targetConversationIDSnapshot, secondary.id)
        XCTAssertEqual(run.harnessIDSnapshot, "codex")
        XCTAssertEqual(run.isExactTargetSnapshot, true)
        XCTAssertEqual(run.snapshotTargetConversation?.id, secondary.id)
        XCTAssertEqual(definition.state, .completed)
        _ = try await engine.claimDue(definitionID: definition.id, at: fixture.date(303))
        XCTAssertEqual(try fixture.runCount(), 1)
        fixture.context.delete(definition)
        try fixture.context.save()
        XCTAssertEqual(run.isExactTargetSnapshot, true)
        XCTAssertEqual(run.snapshotTargetConversation?.id, secondary.id)
    }

    func testSecondaryCallbackApprovalAndDeletionPreventDeliveryToMain() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(path: "/tmp/removed-callback", name: "Callbacks")
        let thread = AgentThread(name: "Caller", project: project)
        let main = Conversation(harness: "codex", thread: thread)
        let secondary = Conversation(harness: "codex", isMain: false, thread: thread)
        thread.conversations = [main, secondary]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(recurrence: .once(fixture.date(300)), nextOccurrenceAt: fixture.date(300))
        definition.destination = .existingThread
        definition.targetThread = thread
        definition.exactTargetConversationID = secondary.id
        let approval = ConversationEventRecord(
            conversationId: secondary.id, type: "tool_approval", content: "session", toolId: "approval",
            toolName: "Bash", conversation: secondary
        )
        fixture.context.insert(approval)
        try fixture.context.save()
        XCTAssertFalse(fixture.makeEngine().targetIsAvailableForClaim(conversationID: secondary.id))
        let originalID = secondary.id
        fixture.context.delete(approval)
        try fixture.context.save()
        let engine = fixture.makeEngine(preflight: { snapshot in
            do {
                try ThreadDetailConversationDeletion.commit(secondary, in: fixture.context, invalidateController: {})
                fixture.context.insert(Conversation(harness: "codex", isMain: false, thread: thread))
                try fixture.context.save()
            } catch { XCTFail("Target removal should commit: \(error)") }
            return scheduledTaskReadyOutcome(for: snapshot)
        })
        _ = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301))
        XCTAssertNil(definition.resolvedTargetConversation)
        XCTAssertEqual(definition.exactTargetConversationID, originalID)
        XCTAssertEqual(definition.state, .paused)
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertEqual(try fixture.runCount(), 0)
        XCTAssertTrue(main.events.isEmpty)
    }
}

@MainActor
private final class CallbackTargetReadiness {
    var ready = false
}
