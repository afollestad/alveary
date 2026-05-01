import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testTokenThresholdPromptsForHandoffSteeringWhenEnabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.inputDraft = "Existing draft"

        triggerAutomaticSessionHandoffThreshold(fixture: fixture)

        try await waitUntil("handoff steering prompt shown after threshold") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.handoffSteeringRestorableDraft, "Existing draft")
        XCTAssertEqual(
            fixture.viewModel.state.handoffSteeringCountdownRemaining,
            AppSettings.defaultHandoffSteeringCountdownSeconds
        )
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).contains { $0.type == "tokens" })
    }

    func testAutomaticSessionHandoffBypassesSteeringWhenDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffSteeringEnabled = false
        }

        triggerAutomaticSessionHandoffThreshold(fixture: fixture)

        try await waitUntil("handoff prompt sent after threshold") {
            await fixture.agentsManager.sentMessages().contains(AppSettings.defaultSessionHandoffPrompt)
        }

        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testHandoffSteeringSubmitStartsHiddenPromptWithSteering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus on prompt entry."))

        try await waitUntil("steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        let hiddenPrompt = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(hiddenPrompt.hasPrefix(AppSettings.defaultSessionHandoffPrompt))
        XCTAssertTrue(hiddenPrompt.contains("## User Handoff Steering"))
        XCTAssertTrue(hiddenPrompt.hasSuffix("Focus on prompt entry."))
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
    }

    func testEmptyHandoffSteeringSubmitStartsHiddenPromptWithoutSteering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(" \n "))

        try await waitUntil("unsteered handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertNil(fixture.viewModel.state.submittedHandoffSteeringPrompt)
    }

    func testHandoffSteeringCountdownExpiryStartsHiddenPromptWithoutSteering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        fixture.viewModel.state.handoffSteeringCountdownRemaining = 0
        await fixture.viewModel.autoSubmitSessionHandoffSteeringPromptIfUnedited()

        try await waitUntil("countdown-submitted handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
    }

    func testHandoffSteeringCountdownCancelsWhenComposerDraftChanges() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        fixture.viewModel.state.inputDraft = "Focus on the generated tests."
        fixture.viewModel.cancelSessionHandoffSteeringCountdownIfDraftChanged(
            to: fixture.viewModel.state.inputDraft
        )

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertNil(fixture.viewModel.state.handoffSteeringCountdownRemaining)
        XCTAssertNil(fixture.viewModel.state.handoffSteeringDraftBaseline)
        XCTAssertTrue(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testSubmittedHandoffSteeringAppendsRawPromptToFreshSessionMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let steeringPrompt = "Focus on prompt entry.\nKeep this exact text."
        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(steeringPrompt))
        try await waitUntil("steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

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
        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("steered handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages[1], "Carry this context forward.\n\n## User Prompt\n" + steeringPrompt)
    }
}

@MainActor
private func triggerAutomaticSessionHandoffThreshold(fixture: ConversationViewModelTestFixture) {
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
