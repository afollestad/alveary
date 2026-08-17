import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testReuseClaimTargetsTheLinkedUnpinnedThreadWithDefinitionSettings() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let thread = AgentThread(
            name: "Rolling thread",
            model: "thread-model",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/reused-workspace",
                ownershipStrategy: .privateOwned
            )
        )
        let conversation = Conversation(id: "reused-main", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.destination = .reusedThread
        definition.reusedThread = thread
        try fixture.context.save()
        let engine = fixture.makeEngine(preflight: { snapshot in
            // Unlike an existing target, the definition stays authoritative for settings —
            // only the conversation identity gates through the reused target.
            XCTAssertNil(snapshot.target)
            XCTAssertEqual(snapshot.reusedTarget?.conversationID, "reused-main")
            XCTAssertEqual(snapshot.model, "gpt-5")
            return scheduledTaskReadyOutcome(for: snapshot)
        })

        guard case .claimed = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        ) else {
            return XCTFail("Expected the reuse claim to succeed without a pin")
        }
        let run = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertEqual(run.targetThread?.persistentModelID, thread.persistentModelID)
        XCTAssertEqual(run.targetConversationIDSnapshot, conversation.id)
        XCTAssertEqual(run.modelSnapshot, "gpt-5")
    }

    func testReuseClaimFallsBackToCreatingWhenTheLinkedThreadIsUnhealthy() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let archived = AgentThread(name: "Archived rolling thread", mode: .task)
        archived.archivedAt = fixture.date(0)
        let archivedConversation = Conversation(id: "archived-main", provider: "codex", thread: archived)
        archived.conversations = [archivedConversation]
        fixture.context.insert(archived)
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.destination = .reusedThread
        definition.reusedThread = archived
        try fixture.context.save()
        let engine = fixture.makeEngine()

        guard case .claimed = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        ) else {
            return XCTFail("Expected the self-heal to claim a creating run instead of blocking")
        }
        let run = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertNil(run.targetThread)
        XCTAssertNil(run.targetConversationIDSnapshot)
    }

    func testBusyReusedThreadDefersTheClaimLikeAnExistingTarget() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let thread = AgentThread(
            name: "Rolling thread",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/busy-reused-workspace",
                ownershipStrategy: .privateOwned
            )
        )
        let conversation = Conversation(id: "busy-reused-main", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        definition.destination = .reusedThread
        definition.reusedThread = thread
        try fixture.context.save()
        let engine = fixture.makeEngine(targetIsReady: { _ in false })

        let waiting = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301))

        guard case .waitingForTarget(let occurrenceAt) = waiting else {
            return XCTFail("Expected the due occurrence to wait for the busy reused thread")
        }
        XCTAssertEqual(occurrenceAt, fixture.date(300))
        XCTAssertEqual(definition.targetWaitStartedAt, fixture.date(301))
        XCTAssertEqual(try fixture.runCount(), 0)
    }

    func testForkedReusedThreadIsTreatedAsGoneRatherThanTargeted() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let thread = AgentThread(
            name: "Forked rolling thread",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/forked-reused-workspace",
                ownershipStrategy: .privateOwned
            )
        )
        let first = Conversation(id: "forked-main-a", provider: "codex", isMain: true, thread: thread)
        let second = Conversation(id: "forked-main-b", provider: "codex", isMain: true, thread: thread)
        thread.conversations = [first, second]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.destination = .reusedThread
        definition.reusedThread = thread
        try fixture.context.save()
        let engine = fixture.makeEngine()

        guard case .claimed = try await engine.claimDue(
            definitionID: definition.id,
            at: fixture.date(301)
        ) else {
            return XCTFail("Expected a forked reuse thread to fall back to creating")
        }
        let run = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertNil(run.targetThread)
    }
}
