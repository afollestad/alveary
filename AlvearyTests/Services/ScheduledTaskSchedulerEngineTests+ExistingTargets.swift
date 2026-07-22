import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testSecondDefinitionCannotClaimSameTargetWhileFirstTargetedRunIsPersisted() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(path: "/tmp/shared-existing-target", name: "Shared target")
        let target = AgentThread(name: "Pinned target", isPinned: true, project: project)
        let conversation = Conversation(id: "shared-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        fixture.context.insert(project)
        let first = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        let second = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        for definition in [first, second] {
            definition.destination = .existingThread
            definition.targetThread = target
        }
        try fixture.context.save()
        let engine = fixture.makeEngine()

        guard case .claimed = try await engine.claimDue(
            definitionID: first.id,
            at: fixture.date(301)
        ) else {
            return XCTFail("Expected the first target run to claim")
        }
        let secondResult = try await engine.claimDue(
            definitionID: second.id,
            at: fixture.date(301)
        )

        guard case .waitingForTarget(let occurrenceAt) = secondResult else {
            return XCTFail("Expected the second definition to wait for the persisted target run")
        }
        XCTAssertEqual(occurrenceAt, fixture.date(300))
        XCTAssertEqual(second.pendingOccurrenceAt, fixture.date(300))
        XCTAssertEqual(try fixture.runCount(), 1)
    }

    func testBusyExistingTargetCoalescesWithoutClaimUntilTargetIsIdle() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let project = Project(path: "/tmp/existing-target", name: "Target Project")
        let target = AgentThread(name: "Pinned target", isPinned: true, project: project)
        target.taskGrantedRoots = ["/tmp/existing-grant"]
        let conversation = Conversation(id: "existing-target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        project.threads = [target]
        fixture.context.insert(project)
        let definition = try fixture.insertDefinition(
            recurrence: .interval(minutes: 5, anchor: fixture.date(0)),
            nextOccurrenceAt: fixture.date(300)
        )
        definition.destination = .existingThread
        definition.targetThread = target
        try fixture.context.save()
        let targetReadiness = ScheduledTargetReadiness()
        let engine = fixture.makeEngine(
            preflight: { snapshot in
                XCTAssertNil(snapshot.model)
                return scheduledTaskReadyOutcome(for: snapshot)
            },
            targetIsReady: { _ in targetReadiness.isReady }
        )

        let waiting = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301))

        guard case .waitingForTarget(let occurrenceAt) = waiting else {
            return XCTFail("Expected the due occurrence to wait for its target")
        }
        XCTAssertEqual(occurrenceAt, fixture.date(300))
        XCTAssertEqual(definition.pendingOccurrenceAt, fixture.date(300))
        XCTAssertEqual(definition.targetWaitStartedAt, fixture.date(301))
        XCTAssertEqual(definition.nextOccurrenceAt, fixture.date(600))
        XCTAssertEqual(try fixture.runCount(), 0)

        targetReadiness.isReady = true
        let claimed = try await engine.claimDue(definitionID: definition.id, at: fixture.date(302))

        guard case .claimed(let runID) = claimed else {
            return XCTFail("Expected the waiting occurrence to claim once idle")
        }
        let run = try XCTUnwrap(fixture.run(id: runID))
        XCTAssertEqual(run.destinationSnapshot, .existingThread)
        XCTAssertEqual(run.targetConversationIDSnapshot, conversation.id)
        XCTAssertNil(run.modelSnapshot)
        XCTAssertEqual(run.grantedRootsSnapshot, ["/tmp/existing-grant"])
        XCTAssertNil(definition.pendingOccurrenceAt)
        XCTAssertNil(definition.targetWaitStartedAt)
    }

    func testUnresolvedPersistedApprovalKeepsExistingTargetWaitingWithoutMutatingApproval() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let target = try insertExistingTarget(in: fixture, suffix: "pending-approval")
        let approval = ConversationEventRecord(
            id: "persisted-approval",
            conversationId: target.conversation.id,
            type: "tool_approval",
            content: "provider-session",
            toolId: "tool-approval",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#,
            timestamp: fixture.date(250),
            conversation: target.conversation
        )
        target.conversation.events = [approval]
        fixture.context.insert(approval)
        try fixture.context.save()

        let result = try await fixture.makeEngine().claimDue(
            definitionID: target.definition.id,
            at: fixture.date(301)
        )

        guard case .waitingForTarget(let occurrenceAt) = result else {
            return XCTFail("Expected an unresolved persisted approval to keep the target waiting")
        }
        XCTAssertEqual(occurrenceAt, fixture.date(300))
        XCTAssertEqual(target.definition.pendingOccurrenceAt, fixture.date(300))
        XCTAssertEqual(target.definition.targetWaitStartedAt, fixture.date(301))
        XCTAssertEqual(try fixture.runCount(), 0)
        XCTAssertEqual(target.conversation.events.map(\.id), [approval.id])
        XCTAssertNil(approval.toolApprovalStatus)
        XCTAssertEqual(approval.toolInput, #"{"command":"pwd"}"#)
    }

    func testUnansweredPersistedPromptKeepsExistingTargetWaitingWithoutMutatingPrompt() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let target = try insertExistingTarget(in: fixture, suffix: "pending-prompt")
        let promptInput = #"{"questions":[{"question":"Continue?","header":"Continue","options":[],"multiSelect":false}]}"#
        let prompt = ConversationEventRecord(
            id: "persisted-prompt",
            conversationId: target.conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            timestamp: fixture.date(250),
            conversation: target.conversation
        )
        target.conversation.events = [prompt]
        fixture.context.insert(prompt)
        try fixture.context.save()

        let result = try await fixture.makeEngine().claimDue(
            definitionID: target.definition.id,
            at: fixture.date(301)
        )

        guard case .waitingForTarget(let occurrenceAt) = result else {
            return XCTFail("Expected an unanswered persisted prompt to keep the target waiting")
        }
        XCTAssertEqual(occurrenceAt, fixture.date(300))
        XCTAssertEqual(target.definition.pendingOccurrenceAt, fixture.date(300))
        XCTAssertEqual(target.definition.targetWaitStartedAt, fixture.date(301))
        XCTAssertEqual(try fixture.runCount(), 0)
        XCTAssertEqual(target.conversation.events.map(\.id), [prompt.id])
        XCTAssertNil(prompt.content)
        XCTAssertEqual(prompt.toolInput, promptInput)
    }

    func testNilStatusApprovalWithLaterToolResultDoesNotBlockExistingTargetClaim() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let target = try insertExistingTarget(in: fixture, suffix: "resolved-approval")
        let approval = ConversationEventRecord(
            id: "resolved-approval",
            conversationId: target.conversation.id,
            type: "tool_approval",
            content: "provider-session",
            toolId: "resolved-tool",
            toolName: "Bash",
            timestamp: fixture.date(250),
            conversation: target.conversation
        )
        let resultRecord = ConversationEventRecord(
            id: "approval-result",
            conversationId: target.conversation.id,
            type: "tool_result",
            toolId: "resolved-tool",
            toolOutput: "done",
            timestamp: fixture.date(251),
            conversation: target.conversation
        )
        target.conversation.events = [approval, resultRecord]
        fixture.context.insert(approval)
        fixture.context.insert(resultRecord)
        try fixture.context.save()

        let result = try await fixture.makeEngine().claimDue(
            definitionID: target.definition.id,
            at: fixture.date(301)
        )

        guard case .claimed = result else {
            return XCTFail("Expected the later tool result to resolve the nil-status approval")
        }
        XCTAssertEqual(try fixture.runCount(), 1)
        XCTAssertNil(target.definition.pendingOccurrenceAt)
        XCTAssertNil(target.definition.targetWaitStartedAt)
        XCTAssertNil(approval.toolApprovalStatus)
        XCTAssertEqual(resultRecord.toolOutput, "done")
    }
}

@MainActor
private func insertExistingTarget(
    in fixture: ScheduledTaskSchedulerFixture,
    suffix: String
) throws -> (definition: ScheduledTask, conversation: Conversation) {
    let project = Project(path: "/tmp/existing-target-\(suffix)", name: "Existing target")
    let thread = AgentThread(name: "Pinned target", isPinned: true, project: project)
    let conversation = Conversation(id: "existing-target-\(suffix)", provider: "codex", thread: thread)
    thread.conversations = [conversation]
    project.threads = [thread]
    fixture.context.insert(project)
    let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
    definition.destination = .existingThread
    definition.targetThread = thread
    try fixture.context.save()
    return (definition, conversation)
}

@MainActor
private final class ScheduledTargetReadiness {
    var isReady = false
}
