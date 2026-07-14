import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class ConversationControllerRegistryTests: XCTestCase {}

extension ConversationControllerRegistryTests {
    func testScheduledTerminalReconciliationDoesNotCreateAnUnmountedController() throws {
        let fixture = try ConversationViewModelTestFixture()
        var factoryCallCount = 0
        let registry = DefaultConversationControllerRegistry { _ in
            factoryCallCount += 1
            return fixture.viewModel
        }

        registry.reconcileScheduledTaskTerminalState(conversationID: fixture.conversation.id)

        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertNil(
            registry.controller(
                for: ConversationControllerKey(conversationID: fixture.conversation.id)
            )
        )
    }

    func testInactiveViewLeasesShareControllerWithoutActivatingLifecycle() throws {
        let fixture = try ConversationViewModelTestFixture()
        var factoryCallCount = 0
        let registry = DefaultConversationControllerRegistry { _ in
            factoryCallCount += 1
            return fixture.viewModel
        }

        let first = registry.makeViewLease(for: fixture.conversation)
        let second = registry.makeViewLease(for: fixture.conversation)

        XCTAssertIdentical(first.viewModel, second.viewModel)
        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertFalse(fixture.viewModel.state.isViewMounted)

        first.activate()
        second.activate()
        XCTAssertTrue(fixture.viewModel.state.isViewMounted)

        first.deactivate()
        first.deactivate()
        XCTAssertTrue(fixture.viewModel.state.isViewMounted)

        second.deactivate()
        XCTAssertFalse(fixture.viewModel.state.isViewMounted)

        let key = first.key
        first.release()
        second.release()
        XCTAssertNil(registry.controller(for: key))
    }

    func testViewAndBackgroundLeasesShareOneSubscriptionAndMountIndependently() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let viewLease = registry.makeViewLease(for: fixture.conversation)
        let backgroundLease = registry.makeBackgroundLease(for: fixture.conversation)

        viewLease.activate()
        backgroundLease.activate()
        try await waitUntil("expected shared subscription") {
            await fixture.agentsManager.subscribeCalls() == 1
        }

        XCTAssertIdentical(viewLease.viewModel, backgroundLease.viewModel)
        XCTAssertTrue(fixture.viewModel.state.isViewMounted)

        viewLease.deactivate()
        XCTAssertFalse(fixture.viewModel.state.isViewMounted)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)

        backgroundLease.deactivate()
        try await waitUntil("expected subscription cancellation") {
            await fixture.agentsManager.subscriptionTerminations() == 1
        }
    }

    func testActiveTurnHandsOffFromViewToInternalBackgroundRetention() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()
        try await waitUntil("expected initial subscription") {
            await fixture.agentsManager.subscribeCalls() == 1
        }

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.deactivate()

        XCTAssertFalse(fixture.viewModel.state.isViewMounted)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)
        let subscriptionTerminations = await fixture.agentsManager.subscriptionTerminations()
        XCTAssertEqual(subscriptionTerminations, 0)
    }

    func testHiddenTurnHandsOffFromViewWithoutPublishingVisibleOutcome() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.beginHiddenActivityTurn()

        lease.release()

        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)
        let subscriptionTerminations = await fixture.agentsManager.subscriptionTerminations()
        XCTAssertEqual(subscriptionTerminations, 0)

        fixture.viewModel.state.endTurn()
        try await waitUntil("expected hidden controller eviction after completion") {
            registry.controller(for: key) == nil
        }
    }

    func testOutcomeStreamTracksActiveWaitingAndTerminalWithoutSecondSubscription() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let active = await outcomes.next()
        XCTAssertEqual(active?.state, .active)

        let approval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "approval-1",
            toolName: "Bash",
            toolInput: "{}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        let waiting = await outcomes.next()
        XCTAssertEqual(waiting?.state, .waitingForApproval(interactionID: "approval-1"))

        fixture.viewModel.state.pendingToolApproval = nil
        fixture.viewModel.state.endTurn()
        let terminal = await outcomes.next()
        XCTAssertEqual(terminal?.state, .terminal(.succeeded))
        let subscribeCalls = await fixture.agentsManager.subscribeCalls()
        XCTAssertEqual(subscribeCalls, 1)
    }

    func testTerminalMaintenanceFlushesThenSuspendsAndEvictsReleasedController() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()
        fixture.viewModel.state.endTurn()

        try await waitUntil("expected terminal maintenance") {
            recorder.values == ["flush", "suspend"] && registry.controller(for: key) == nil
        }
    }

    func testNextVisibleTurnRetriesMaintenanceWithoutRewritingFailedOutcome() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder(flushFailuresRemaining: 1)
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in try recorder.flush() },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let active = await outcomes.next()
        fixture.viewModel.state.endTurn()

        try await waitUntil("expected failed terminal flush to retain controller") {
            recorder.values == ["flush"] && registry.controller(for: key) != nil
        }
        let failed = await outcomes.next()
        XCTAssertEqual(failed?.turn, active?.turn)
        guard case .terminal(.failed) = failed?.state else {
            XCTFail("Expected one failed terminal outcome after the flush failure")
            return
        }
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let nextActive = await outcomes.next()
        XCTAssertEqual(nextActive?.state, .active)
        XCTAssertNotEqual(nextActive?.turn, failed?.turn)
        try await waitUntil("expected next turn to retry terminal maintenance") {
            recorder.values == ["flush", "flush"]
        }

        fixture.viewModel.state.endTurn()
        let nextTerminal = await outcomes.next()
        XCTAssertEqual(nextTerminal?.turn, nextActive?.turn)
        XCTAssertEqual(nextTerminal?.state, .terminal(.succeeded))
        try await waitUntil("expected retried controller to suspend after the next turn") {
            recorder.values == ["flush", "flush", "flush", "suspend"] && registry.controller(for: key) != nil
        }
    }

    func testQueuedDrainPreservesBothTurnBoundariesAndDefersSuspension() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let firstActive = await outcomes.next()
        fixture.viewModel.queueDrainTask = Task { try? await Task.sleep(for: .seconds(5)) }
        fixture.viewModel.state.endTurn()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        lease.release()

        let firstTerminal = await outcomes.next()
        let secondActive = await outcomes.next()
        XCTAssertEqual(firstTerminal?.turn, firstActive?.turn)
        XCTAssertEqual(firstTerminal?.state, .terminal(.succeeded))
        XCTAssertEqual(secondActive?.state, .active)
        XCTAssertNotEqual(secondActive?.turn, firstActive?.turn)
        XCTAssertEqual(recorder.values, ["flush"])
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)

        fixture.viewModel.queueDrainTask?.cancel()
        fixture.viewModel.queueDrainTask = nil
        fixture.viewModel.state.endTurn()
        let secondTerminal = await outcomes.next()
        XCTAssertEqual(secondTerminal?.turn, secondActive?.turn)
        XCTAssertEqual(secondTerminal?.state, .terminal(.succeeded))
        try await waitUntil("expected suspension after queued drain finishes") {
            recorder.values == ["flush", "flush", "suspend"] && registry.controller(for: key) == nil
        }
    }

}

extension ConversationControllerRegistryTests {
    func testTerminalOutcomeWaitsForDurableFlush() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let gate = ControllerFlushGate()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in await gate.flush() },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        let collector = ControllerOutcomeCollector(stream: lease.outcomes())

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        try await waitUntil("expected active outcome") { collector.values.count == 1 }
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected terminal flush to start") { gate.flushCallCount == 1 }

        XCTAssertEqual(collector.values.map(\.state), [.active])
        gate.open()
        try await waitUntil("expected terminal outcome after flush") { collector.values.count == 2 }
        XCTAssertEqual(collector.values.map(\.state), [.active, .terminal(.succeeded)])
    }

    func testSynchronousTurnReplacementDoesNotLoseTerminalBoundaryOrFailureCause() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let firstActive = await outcomes.next()

        fixture.viewModel.controllerTerminalFailureMessage = "First turn failed"
        fixture.viewModel.state.endTurn()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()

        let firstTerminal = await outcomes.next()
        let secondActive = await outcomes.next()
        XCTAssertEqual(firstTerminal?.turn, firstActive?.turn)
        XCTAssertEqual(firstTerminal?.state, .terminal(.failed(message: "First turn failed")))
        XCTAssertEqual(secondActive?.state, .active)
        XCTAssertNotEqual(secondActive?.turn, firstActive?.turn)
    }

    func testPersistenceScheduledDuringTerminalFlushVetoesSuspension() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let gate = ControllerFlushGate()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in
                await gate.flush()
                recorder.record("flush")
            },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        fixture.viewModel.state.endTurn()
        try await waitUntil("expected first flush to start") { gate.flushCallCount == 1 }
        fixture.viewModel.saveTask = Task { try? await Task.sleep(for: .seconds(5)) }
        gate.open()

        try await waitUntil("expected first flush to finish") { recorder.values == ["flush"] }
        XCTAssertFalse(recorder.values.contains("suspend"))
        fixture.viewModel.saveTask?.cancel()
        fixture.viewModel.saveTask = nil

        try await waitUntil("expected trailing persistence flush before suspension") {
            recorder.values == ["flush", "flush", "suspend"]
        }
    }

    func testPausedGoalRetainsControllerAndRuntimeUntilGoalBecomesTerminal() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Earlier request",
            conversation: try fixture.dbConversation()
        ))
        try fixture.context.save()
        let recorder = ControllerMaintenanceRecorder()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in recorder.record("flush") },
            suspendRuntime: { _ in recorder.record("suspend") },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.setGoalModeArmed(true)
        try await fixture.viewModel.startGoal(
            "Keep working",
            supportsExistingSessionGoalStart: true
        )
        let active = await outcomes.next()
        XCTAssertEqual(active?.state, .active)
        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Keep working",
            status: .paused,
            availableActions: [.resume, .delete]
        )
        lease.release()

        await Task.yield()
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)
        XCTAssertTrue(recorder.values.isEmpty)

        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Keep working",
            status: .achieved
        )
        try await waitUntil("expected terminal goal to allow suspension") {
            recorder.values == ["flush", "suspend"] && registry.controller(for: key) == nil
        }
    }

    func testPendingSaveRetainsReleasedControllerUntilPersistenceFinishes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        fixture.viewModel.saveTask = Task {}

        lease.release()
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)

        fixture.viewModel.saveTask = nil
        try await waitUntil("expected controller eviction after save") {
            registry.controller(for: key) == nil
        }
    }

    func testWaitingQuestionRetainsControllerAfterExternalLeaseRelease() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        let key = lease.key
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.state.grouper.items = [
            .promptBlock(
                id: "prompt-block",
                prompt: PromptEntry(id: "question-1", questions: [], submittedSummary: nil)
            )
        ]
        let waiting = await outcomes.next()
        lease.release()

        await Task.yield()
        XCTAssertEqual(waiting?.state, .waitingForQuestion(interactionID: "question-1"))
        XCTAssertIdentical(registry.controller(for: key), fixture.viewModel)
        XCTAssertTrue(fixture.viewModel.hasActivatedBackgroundLifecycle)
    }

    func testOutcomeStreamReportsInterruptedTerminalBoundary() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry(
            makeViewModel: { _ in fixture.viewModel },
            flushTerminalRecords: { _ in },
            suspendRuntime: { _ in },
            runtimeIsSuspended: { _ in true }
        )
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        _ = await outcomes.next()

        fixture.viewModel.state.lastTurnInterrupted = true
        fixture.viewModel.state.endTurn()

        let interrupted = await outcomes.next()
        XCTAssertEqual(interrupted?.state, .interrupted)
    }

    func testTerminationFlushCompletesSynchronously() throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()

        let failures = registry.flushForTermination()

        XCTAssertTrue(failures.isEmpty)
    }

    func testInvalidationDeactivatesLifecyclesAndFinishesOutcomeStreams() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeViewLease(for: fixture.conversation)
        lease.activate()
        var outcomes = lease.outcomes().makeAsyncIterator()

        registry.invalidate(for: lease.key)

        XCTAssertFalse(fixture.viewModel.state.isViewMounted)
        XCTAssertNil(registry.controller(for: lease.key))
        let outcomeAfterInvalidation = await outcomes.next()
        XCTAssertNil(outcomeAfterInvalidation)
    }
}
