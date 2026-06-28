import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testVisibleUserSendUsesVisibleActivityVisibility() async throws {
        let fixture = try ConversationViewModelTestFixture()

        try await fixture.viewModel.send("Fix the sidebar ordering")

        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        XCTAssertEqual(sendVisibilities, [.visible])
    }

    func testHiddenSessionHandoffUsesHiddenActivityVisibilityAndDoesNotRecordVisibleOutbound() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(threadActivityRecorder: recorder)

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        XCTAssertEqual(sendVisibilities, [.hidden])
        XCTAssertTrue(recorder.visibleOutboundConversationIDs.isEmpty)
    }

    func testInitialPromptSetupRecordsVisibleOutboundAfterSetupCompletes() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            threadActivityRecorder: recorder
        )

        try await fixture.viewModel.setupAndStart("Start the implementation")

        XCTAssertEqual(recorder.visibleOutboundConversationIDs, [fixture.conversation.id])
        XCTAssertTrue(recorder.visibleTurnEndedConversationIDs.isEmpty)
    }

    func testCancelledInitialPromptSetupDoesNotRecordVisibleOutbound() async throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(
            useWorktree: true,
            hasCompletedInitialSetup: false,
            pausesWorktreeCreate: true,
            threadActivityRecorder: recorder
        )

        let sendTask = Task {
            try await fixture.viewModel.queueOrSend("Start the implementation")
        }

        for _ in 0..<50 where fixture.viewModel.setupPhase == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        await fixture.viewModel.cancel()

        do {
            try await sendTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        }

        XCTAssertTrue(recorder.visibleOutboundConversationIDs.isEmpty)
        XCTAssertTrue(recorder.visibleTurnEndedConversationIDs.isEmpty)
    }

    func testLocalVisibleTurnEndRecordsThreadActivityOnce() throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(threadActivityRecorder: recorder)

        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.markPromptDismissInterruption()
        fixture.viewModel.markPromptDismissInterruption()

        XCTAssertEqual(recorder.visibleTurnEndedConversationIDs, [fixture.conversation.id])
    }

    func testPromptDismissInterruptionPausesQueuedMessagesBeforeVisibleTurnEnds() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.messageQueue.enqueue("Queued follow-up", stagedContext: nil)

        fixture.viewModel.markPromptDismissInterruption()

        XCTAssertEqual(fixture.viewModel.state.queuedMessagesPauseReason, .interrupted)
        XCTAssertEqual(fixture.viewModel.state.currentTurnActivityVisibility, .hidden)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued follow-up"])
    }

    func testLocalHiddenTurnEndDoesNotRecordThreadActivity() throws {
        let recorder = RecordingThreadActivityRecorder()
        let fixture = try ConversationViewModelTestFixture(threadActivityRecorder: recorder)

        fixture.viewModel.beginHiddenActivityTurn()
        fixture.viewModel.markPromptDismissInterruption()

        XCTAssertTrue(recorder.visibleTurnEndedConversationIDs.isEmpty)
    }
}
