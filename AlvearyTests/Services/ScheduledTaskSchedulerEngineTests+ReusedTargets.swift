import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerEngineTests {
    func testReuseClaimScopesOnlyOpenCodeDiscoveryToItsExecutionDirectory() async throws {
        for harnessID in ["opencode", "codex"] {
            let fixture = try ScheduledTaskSchedulerFixture()
            let thread = AgentThread(
                name: "Reused", mode: .task,
                taskWorkspaceDescriptor: TaskWorkspaceDescriptor(primaryRoot: "/tmp/reused-workspace", ownershipStrategy: .privateOwned)
            )
            thread.conversations = [Conversation(id: "reused-main", harness: harnessID, thread: thread)]
            fixture.context.insert(thread)
            let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
            definition.destination = .reusedThread
            definition.harnessID = harnessID
            definition.reusedThread = thread
            try fixture.context.save()
            let engine = fixture.makeEngine(preflight: { snapshot in
                XCTAssertNil(snapshot.projectPath)
                XCTAssertEqual(snapshot.workspaceKind, .privateWorkspace)
                XCTAssertEqual(snapshot.reusedTarget?.harnessDiscoveryDirectory, harnessID == "opencode" ? "/tmp/reused-workspace" : nil)
                return scheduledTaskReadyOutcome(for: snapshot)
            })

            guard case .claimed = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301)) else {
                return XCTFail("Expected the reused claim to keep its workspace")
            }
        }
    }

    func testReusedOpenCodeDirectoryChangeDuringPreflightCannotClaim() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let thread = AgentThread(
            name: "Reused", mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(primaryRoot: "/tmp/reused-workspace", ownershipStrategy: .privateOwned)
        )
        thread.conversations = [Conversation(id: "reused-main", harness: "opencode", thread: thread)]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.destination = .reusedThread
        definition.harnessID = "opencode"
        definition.reusedThread = thread
        try fixture.context.save()
        let engine = fixture.makeEngine(preflight: { snapshot in
            XCTAssertEqual(snapshot.reusedTarget?.harnessDiscoveryDirectory, "/tmp/reused-workspace")
            thread.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(primaryRoot: "/tmp/replacement-workspace", ownershipStrategy: .privateOwned)
            return scheduledTaskReadyOutcome(for: snapshot)
        })

        let outcome = try await engine.claimDue(definitionID: definition.id, at: fixture.date(301))

        guard case .changedDuringPreflight = outcome else { return XCTFail("Expected the stale discovery scope to prevent claiming") }
        XCTAssertEqual(try fixture.runCount(), 0)
    }

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
        let conversation = Conversation(id: "reused-main", harness: "codex", thread: thread)
        thread.conversations = [conversation]
        fixture.context.insert(thread)
        let definition = try fixture.insertDefinition(nextOccurrenceAt: fixture.date(300))
        definition.destination = .reusedThread
        definition.reusedThread = thread
        // The first run upgraded this legacy definition's created thread to explicitly managed roots.
        definition.workspaceSnapshot = WorkspaceSnapshot(primarySource: nil, rootsExplicitlyManaged: false)
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
        XCTAssertEqual(run.workspaceSnapshot, thread.workspaceSnapshot)
        XCTAssertTrue(try XCTUnwrap(run.workspaceSnapshot).rootsExplicitlyManaged)
    }

    func testReuseClaimFallsBackToCreatingWhenTheLinkedThreadIsUnhealthy() async throws {
        let fixture = try ScheduledTaskSchedulerFixture()
        let archived = AgentThread(name: "Archived rolling thread", mode: .task)
        archived.archivedAt = fixture.date(0)
        let archivedConversation = Conversation(id: "archived-main", harness: "codex", thread: archived)
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
        let conversation = Conversation(id: "busy-reused-main", harness: "codex", thread: thread)
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
        let first = Conversation(id: "forked-main-a", harness: "codex", isMain: true, thread: thread)
        let second = Conversation(id: "forked-main-b", harness: "codex", isMain: true, thread: thread)
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
