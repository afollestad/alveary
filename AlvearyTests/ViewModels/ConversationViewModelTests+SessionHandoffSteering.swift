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
        XCTAssertEqual(fixture.viewModel.state.sessionHandoffRestorableDraft, "Existing draft")
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

    func testCommandHandoffWithExplicitSteeringHonorsSteeringWhenAutomaticSteeringIsDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.contextManagementEnabled = false
            $0.handoffSteeringEnabled = false
        }

        XCTAssertTrue(fixture.viewModel.triggerSessionHandoffFromCommand(steeringPrompt: "Focus on tests."))

        try await waitUntil("command handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        let hiddenPrompt = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(hiddenPrompt.contains("## User Handoff Steering"))
        XCTAssertTrue(hiddenPrompt.hasSuffix("Focus on tests."))
    }

    func testCommandHandoffPromptsForSteeringWhenAutomaticSteeringIsDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.contextManagementEnabled = false
            $0.handoffSteeringEnabled = false
        }

        XCTAssertTrue(fixture.viewModel.triggerSessionHandoffFromCommand())

        try await waitUntil("command handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertNil(fixture.viewModel.state.handoffSteeringCountdownRemaining)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testCommandHandoffStartsWhenAutomaticHandoffIsDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.contextManagementEnabled = false
        }

        XCTAssertTrue(fixture.viewModel.triggerSessionHandoffFromCommand(steeringPrompt: "Focus the next session."))

        try await waitUntil("command handoff prompt sent while automatic handoff disabled") {
            await fixture.agentsManager.sentMessages().count == 1
        }
    }

    func testCommandHandoffBlockedByActiveTurnShowsError() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()

        XCTAssertFalse(fixture.viewModel.triggerSessionHandoffFromCommand())

        XCTAssertEqual(
            fixture.viewModel.lastTurnError,
            "Wait for the current conversation action to finish before triggering session handoff."
        )
    }

    func testHandoffSteeringSubmitStartsHiddenPromptWithSteering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus on prompt entry."))
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.submitSessionHandoffSteeringPrompt("Duplicate submit."))

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

    func testSteeredHandoffKeepsHiddenTrafficInvisibleAndQueuedMessagesBehindSeed() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued after handoff", stagedContext: nil)
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let steeringPrompt = "Focus on queue ordering."
        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(steeringPrompt))
        try await waitUntil("steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        fixture.viewModel.handleEvent(.messageChunk(text: "Partial hidden response.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "Seed the fresh session.",
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

        let recordsBeforeSeed = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(recordsBeforeSeed.first { $0.role == "assistant" })
        XCTAssertNil(recordsBeforeSeed.first { $0.role == "user" })
        XCTAssertTrue(recordsBeforeSeed.contains { ConversationSessionHandoff.isDisplayMessage($0.content) })

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("steered handoff output sent") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages[1], "Seed the fresh session.\n\n## User Prompt\n" + steeringPrompt)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after handoff"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Seed the fresh session.\n\n## User Prompt\n" + steeringPrompt])
        let recordsAfterSeed = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(recordsAfterSeed.first { $0.role == "assistant" })
    }

    func testFailedSteeredHandoffRetryPreservesSubmittedSteering() async throws {
        let fixture = try ConversationViewModelTestFixture()
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let steeringPrompt = "Focus retry on the submitted steering."
        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt(steeringPrompt))
        try await waitUntil("first steered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))
        XCTAssertEqual(
            fixture.viewModel.state.submittedHandoffSteeringPrompt,
            steeringPrompt
        )

        fixture.viewModel.retryFailedSessionHandoff()
        try await waitUntil("steered handoff prompt retried") {
            await fixture.agentsManager.sentMessages().count == 2
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages[0].contains("## User Handoff Steering"))
        XCTAssertTrue(sentMessages[0].hasSuffix(steeringPrompt))
        XCTAssertTrue(sentMessages[1].contains("## User Handoff Steering"))
        XCTAssertTrue(sentMessages[1].hasSuffix(steeringPrompt))
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testSteeredHandoffGeneratedResultCountdownUsesPromptSendSettingOnly() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffSteeringCountdownSeconds = AppSettings.supportedHandoffSteeringCountdownRange.lowerBound
            $0.handoffPromptSendCountdownSeconds = 22
        }
        triggerAutomaticSessionHandoffThreshold(fixture: fixture)
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus on the outgoing seed."))
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

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Carry this context forward.")
        XCTAssertEqual(fixture.viewModel.state.handoffCountdownRemaining, 22)

        fixture.viewModel.state.inputDraft = "Edited handoff context."
        fixture.viewModel.cancelSessionHandoffSteeringCountdownIfDraftChanged(to: fixture.viewModel.state.inputDraft)
        fixture.viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: fixture.viewModel.state.inputDraft)

        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertEqual(fixture.viewModel.state.submittedHandoffSteeringPrompt, "Focus on the outgoing seed.")
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
