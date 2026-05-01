import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomaticHandoffWithoutSteeringRestoresInterruptedComposerDraftAfterSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffSteeringEnabled = false
        }
        fixture.viewModel.state.inputDraft = "Interrupted visible draft."

        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("unsteered handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.sessionHandoffRestorableDraft, "Interrupted visible draft.")

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("unsteered handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages[1], "Carry this context forward.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Interrupted visible draft.")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testSteeredHandoffAutoSendRestoresInterruptedComposerDraftAfterSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Interrupted visible draft."
        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let steeringPrompt = "Focus on preserving the draft."
        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(steeringPrompt))
        try await waitUntil("steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("steered handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Interrupted visible draft.")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testSteeredHandoffManualEditedSeedRestoresInterruptedComposerDraftAfterSend() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Interrupted visible draft."
        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus on preserving the draft."))
        try await waitUntil("steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.inputDraft = "Edited handoff context."
        fixture.viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: fixture.viewModel.state.inputDraft)
        XCTAssertTrue(fixture.viewModel.prepareManualSessionHandoffSendIfNeeded())
        let outboundMessage = fixture.viewModel.state.inputDraft
        fixture.viewModel.state.inputDraft = ""
        try await fixture.viewModel.sendSessionHandoffOutput(outboundMessage)

        try await waitUntil("edited steered handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(
            sentMessages[1],
            "Edited handoff context.\n\n## User Prompt\nFocus on preserving the draft."
        )
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Interrupted visible draft.")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testFailedSteeredHandoffRetryRestoresLatestVisibleDraftAfterSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Original interrupted draft."
        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let steeringPrompt = "Focus retry on preserving the visible draft."
        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(steeringPrompt))
        try await waitUntil("first steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Original interrupted draft.")

        fixture.viewModel.state.inputDraft = "Edited interrupted draft."
        fixture.viewModel.retryFailedSessionHandoff()
        try await waitUntil("steered handoff prompt retried") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.sessionHandoffRestorableDraft, "Edited interrupted draft.")

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff retry finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("retried handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 3
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Edited interrupted draft.")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testFailedSteeredHandoffRetryKeepsDraftClearedAfterSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Original interrupted draft."
        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus retry on draft clearing."))
        try await waitUntil("first steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Original interrupted draft.")

        fixture.viewModel.state.inputDraft = ""
        fixture.viewModel.retryFailedSessionHandoff()
        try await waitUntil("steered handoff prompt retried") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff retry finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("retried handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 3
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testFailedSkippedSteeringRetryRestoresLatestVisibleDraftAfterSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Original interrupted draft."
        triggerAutomaticSessionHandoffThresholdForDrafts(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(""))
        try await waitUntil("first unsteered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Original interrupted draft.")
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)

        fixture.viewModel.state.inputDraft = "Edited interrupted draft."
        fixture.viewModel.retryFailedSessionHandoff()
        try await waitUntil("unsteered handoff prompt retried") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.sessionHandoffRestorableDraft, "Edited interrupted draft.")

        completeHiddenSessionHandoffResponse(fixture: fixture)
        try await waitUntil("session handoff retry finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("retried handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 3
        }
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Edited interrupted draft.")
        XCTAssertNil(fixture.viewModel.state.sessionHandoffRestorableDraft)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }
}

@MainActor
private func completeHiddenSessionHandoffResponse(fixture: ConversationViewModelTestFixture) {
    fixture.viewModel.handleEvent(.message(
        role: "assistant",
        content: "Carry this context forward.",
        parentToolUseId: nil
    ))
    fixture.viewModel.handleEvent(.tokens(
        input: 10,
        output: 5,
        cacheRead: 0,
        isError: false,
        stopReason: "end_turn",
        durationMs: 10,
        costUsd: 0.01,
        contextWindowSize: 200,
        permissionDenials: []
    ))
}

@MainActor
private func triggerAutomaticSessionHandoffThresholdForDrafts(fixture: ConversationViewModelTestFixture) {
    fixture.viewModel.handleEvent(.tokens(
        input: 180,
        output: 5,
        cacheRead: 0,
        isError: false,
        stopReason: "end_turn",
        durationMs: 10,
        costUsd: 0.01,
        contextWindowSize: 200,
        permissionDenials: []
    ))
}
