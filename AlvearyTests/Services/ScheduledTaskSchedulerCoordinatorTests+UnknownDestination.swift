import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskSchedulerCoordinatorTests {
    func testUnknownDestinationTerminalMutationReconcilesAllRetainedThreadRelationships() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let setup = try insertUnknownDestinationRun(in: fixture)
        let run = setup.run
        let conversations = setup.conversations
        var reconciledConversationIDs: [String] = []
        let services = fixture.makeServices(terminalConversationReconciliation: {
            reconciledConversationIDs.append($0)
        })

        await services.coordinator.persistTerminalResult(
            .failed(message: "Unknown destination failed"),
            runID: run.persistentModelID,
            finishedAt: fixture.actionDate
        )

        XCTAssertEqual(run.status, .failure)
        XCTAssertTrue(conversations.allSatisfy { !$0.isUnread })
        XCTAssertEqual(Set(reconciledConversationIDs), Set(conversations.map(\.id)))
    }

    func testInvalidExistingTargetPresentationStillReconcilesTargetSiblings() async throws {
        let fixture = try ScheduledTaskCoordinatorFixture()
        let setup = try insertInvalidExistingTargetRun(in: fixture)
        var reconciledConversationIDs: [String] = []
        let services = fixture.makeServices(terminalConversationReconciliation: {
            reconciledConversationIDs.append($0)
        })

        await services.coordinator.persistTerminalResult(
            .failed(message: "Invalid target failed"),
            runID: setup.run.persistentModelID,
            finishedAt: fixture.actionDate
        )

        XCTAssertEqual(setup.run.status, .failure)
        XCTAssertTrue(setup.conversations.allSatisfy { !$0.isUnread })
        XCTAssertEqual(Set(reconciledConversationIDs), Set(setup.conversations.map(\.id)))
    }
}

@MainActor
private extension ScheduledTaskSchedulerCoordinatorTests {
    func insertUnknownDestinationRun(
        in fixture: ScheduledTaskCoordinatorFixture
    ) throws -> (run: ScheduledTaskRun, conversations: [Conversation]) {
        let run = ScheduledTaskRun(
            occurrenceID: "unknown-terminal-occurrence",
            definitionID: "unknown-terminal-definition",
            definitionRevision: 1,
            occurrenceAt: fixture.actionDate,
            triggerKind: .scheduled,
            status: .running,
            titleSnapshot: "Unknown destination",
            promptSnapshot: "Run work",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "medium",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        let taskThread = AgentThread(name: "Retained task", mode: .task, scheduledTaskRun: run)
        let taskMain = Conversation(id: "unknown-task-main", isMain: true, thread: taskThread)
        taskThread.conversations = [taskMain]
        run.thread = taskThread
        let targetThread = AgentThread(name: "Retained target", isPinned: true)
        let targetMain = Conversation(id: "unknown-live-target-main", isMain: true, thread: targetThread)
        let targetSibling = Conversation(id: "unknown-live-target-sibling", isMain: false, thread: targetThread)
        targetThread.conversations = [targetMain, targetSibling]
        run.targetConversationIDSnapshot = targetMain.id
        run.targetThread = targetThread
        run.destinationRawValueSnapshot = "future-destination"
        fixture.context.insert(run)
        fixture.context.insert(taskThread)
        fixture.context.insert(taskMain)
        fixture.context.insert(targetThread)
        fixture.context.insert(targetMain)
        fixture.context.insert(targetSibling)
        try fixture.context.save()
        return (run, [taskMain, targetMain, targetSibling])
    }

    func insertInvalidExistingTargetRun(
        in fixture: ScheduledTaskCoordinatorFixture
    ) throws -> (run: ScheduledTaskRun, conversations: [Conversation]) {
        let run = ScheduledTaskRun(
            occurrenceID: "invalid-target-occurrence",
            definitionID: "invalid-target-definition",
            definitionRevision: 1,
            occurrenceAt: fixture.actionDate,
            triggerKind: .scheduled,
            status: .running,
            titleSnapshot: "Invalid target",
            promptSnapshot: "Run work",
            destinationSnapshot: .existingThread,
            targetConversationIDSnapshot: "missing-main",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "medium",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
        let target = AgentThread(name: "Retained invalid target", isPinned: true)
        let main = Conversation(id: "invalid-live-target-main", isMain: true, thread: target)
        let sibling = Conversation(id: "invalid-live-target-sibling", isMain: false, thread: target)
        target.conversations = [main, sibling]
        run.targetThread = target
        fixture.context.insert(run)
        fixture.context.insert(target)
        fixture.context.insert(main)
        fixture.context.insert(sibling)
        try fixture.context.save()
        return (run, [main, sibling])
    }
}
