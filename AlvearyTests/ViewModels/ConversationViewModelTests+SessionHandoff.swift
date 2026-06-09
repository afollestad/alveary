import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomaticSessionHandoffDoesNotTriggerWhenDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.contextManagementEnabled = false
        }

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

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testAutomaticSessionHandoffDoesNotTriggerBelowThreshold() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.tokens(
            input: 100,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testHiddenSessionHandoffCapturesResponseStartsFreshSessionAndShowsCountdown() async throws {
        let fixture = try ConversationViewModelTestFixture()

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        let sentMessages = await fixture.agentsManager.sentMessages()
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertEqual(sentMessages, [AppSettings.defaultSessionHandoffPrompt])
        XCTAssertEqual(freshSessionCalls.count, 1)

        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Carry this context forward.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Carry this context forward.")
        XCTAssertEqual(
            fixture.viewModel.state.handoffCountdownRemaining,
            AppSettings.defaultHandoffPromptSendCountdownSeconds
        )

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(records.first { $0.role == "assistant" })
        XCTAssertNil(records.first { $0.role == "user" })
        XCTAssertTrue(records.contains { $0.type == ConversationEventRecord.contextWindowInvalidatedType })
        XCTAssertTrue(records.contains { ConversationSessionHandoff.isDisplayMessage($0.content) })
        let noteRecord = try XCTUnwrap(records.first { ConversationSessionHandoff.isDisplayMessage($0.content) })
        XCTAssertTrue(fixture.viewModel.state.grouper.items.contains(.centeredNote(id: noteRecord.id, kind: .sessionHandoff)))
    }

    func testSessionHandoffPromptSendCountdownUsesPromptSendSetting() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffSteeringCountdownSeconds = AppSettings.supportedHandoffSteeringCountdownRange.lowerBound
            $0.handoffPromptSendCountdownSeconds = 12
        }

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Carry this context forward.")
        XCTAssertEqual(fixture.viewModel.state.handoffCountdownRemaining, 12)
    }

    func testSessionHandoffClearsSessionContinuityNotice() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.sessionContinuityNotice = "Claude restarted with a fresh session."

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        XCTAssertNil(fixture.viewModel.state.sessionContinuityNotice)
    }

    func testHiddenSessionHandoffErrorSurfacesRetryWithoutStartingFreshSession() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))

        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Session handoff failed: handoff prompt failed")
        XCTAssertEqual(
            fixture.viewModel.state.failedSessionHandoffMessage,
            "Session handoff failed: handoff prompt failed"
        )
        XCTAssertTrue(fixture.viewModel.canRetryFailedSessionHandoff)
        XCTAssertTrue(fixture.viewModel.state.hasActiveSessionHandoff)
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(freshSessionCalls.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testFailedSessionHandoffBlocksVisibleSendUntilRetried() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))

        do {
            try await fixture.viewModel.send("Visible follow-up")
            XCTFail("Expected failed handoff recovery to block visible sends")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [AppSettings.defaultSessionHandoffPrompt])
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testFailedSessionHandoffBlocksQueueingAdditionalMessages() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.messageQueue.enqueue("Existing queued message", stagedContext: nil)
        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))

        do {
            try await fixture.viewModel.queueOrSend("Visible follow-up")
            XCTFail("Expected failed handoff recovery to block queueing")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Existing queued message"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [AppSettings.defaultSessionHandoffPrompt])
    }

    func testFailedSessionHandoffRetryRerunsHiddenFlowAndOnlyStartsFreshSessionAfterSuccess() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))

        fixture.viewModel.retryFailedSessionHandoff()
        XCTAssertTrue(fixture.viewModel.state.hasActiveSessionHandoff)

        do {
            try await fixture.viewModel.send("Visible follow-up")
            XCTFail("Expected retrying handoff recovery to keep visible sends blocked")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session handoff is in progress"))
        }

        try await waitUntil("handoff prompt retried") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                AppSettings.defaultSessionHandoffPrompt
            ]
        }
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        let freshSessionCallsBeforeSuccess = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(freshSessionCallsBeforeSuccess.isEmpty)

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Carry this context forward.", parentToolUseId: nil))
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

        try await waitUntil("session handoff retry finished hidden response") {
            await fixture.agentsManager.freshSessionCalls().count == 1
        }
    }

    func testBufferedHiddenSessionHandoffChunksDoNotRenderStreamingBubble() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.isHandingOffSession = true
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Hel", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "lo", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.message(role: "assistant", content: "Hello", parentToolUseId: nil))

        try await waitUntil("hidden handoff response captured", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.state.hiddenHandoffResponse == "Hello"
        }

        XCTAssertNil(fixture.viewModel.streamingText)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(records.first { $0.role == "assistant" })
    }

    func testHiddenSessionHandoffKeepsStreamedChunksWhenFinalAssistantMessageIsEmpty() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") { await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt] }

        fixture.viewModel.handleEvent(.messageChunk(text: "Collected ", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "context.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.message(role: "assistant", content: "", parentToolUseId: nil))
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
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Collected context.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Collected context.")
    }

    func testSessionHandoffCountdownCancelsWhenComposerDraftChanges() async throws {
        let fixture = try ConversationViewModelTestFixture()
        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        fixture.viewModel.state.inputDraft = "Edited handoff context"
        fixture.viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: fixture.viewModel.state.inputDraft)

        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Carry this context forward.")
        XCTAssertNil(fixture.viewModel.state.handoffDraftBaseline)
    }

    func testEditedSessionHandoffDraftStillBypassesExistingQueueWhenSentManually() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued after handoff", stagedContext: nil)
        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        fixture.viewModel.state.inputDraft = "Edited handoff context"
        fixture.viewModel.cancelSessionHandoffCountdownIfDraftChanged(to: fixture.viewModel.state.inputDraft)

        XCTAssertTrue(fixture.viewModel.prepareManualSessionHandoffSendIfNeeded())
        try await fixture.viewModel.sendSessionHandoffOutput(fixture.viewModel.state.inputDraft)

        try await waitUntil("edited handoff output sent before queued message") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Edited handoff context"
            ]
        }

        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after handoff"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Edited handoff context"])
    }

    func testSessionHandoffSendFailureBeforeTranscriptAttemptRestoresHandoffMarker() async throws {
        let fixture = try ConversationViewModelTestFixture()
        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Carry this context forward.")

        XCTAssertTrue(fixture.viewModel.prepareManualSessionHandoffSendIfNeeded())
        fixture.viewModel.state.isReconfiguringSession = true

        do {
            try await fixture.viewModel.sendSessionHandoffOutput("Edited handoff context")
            XCTFail("Expected handoff send to fail while session changes are active")
        } catch {
            XCTAssertEqual(error as? AgentError, AgentError.spawnFailed("Session changes are still being applied"))
        }

        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Edited handoff context")
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testSessionHandoffAutoSendClearsComposerDraft() async throws {
        let fixture = try ConversationViewModelTestFixture()
        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Auto-send this context.")

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("handoff output auto-sent") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Auto-send this context."
            ]
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Auto-send this context."])
    }

    func testSessionHandoffAutoSendBypassesExistingQueueToSeedFreshSession() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.messageQueue.enqueue("Queued after handoff", stagedContext: nil)
        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Seed the fresh session.")

        fixture.viewModel.state.handoffCountdownRemaining = 0
        await fixture.viewModel.autoSendSessionHandoffOutputIfUnedited()

        try await waitUntil("handoff output sent before queued message") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Seed the fresh session."
            ]
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after handoff"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Seed the fresh session."])
    }

    func testSessionHandoffImmediateModeSendsCapturedOutputIntoFreshSession() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffContextCustomizationEnabled = false
        }

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Send this immediately.")

        try await waitUntil("handoff output sent immediately") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Send this immediately."
            ]
        }

        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Send this immediately."])
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertEqual(freshSessionCalls.count, 1)
    }

    func testZeroSecondPromptSendCountdownImmediatelySendsCapturedOutputIntoFreshSession() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffContextCustomizationEnabled = true
            $0.handoffPromptSendCountdownSeconds = 0
        }

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Send this immediately.")

        try await waitUntil("zero countdown handoff output sent immediately") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Send this immediately."
            ]
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Send this immediately."])
    }

    func testSessionHandoffImmediateModeBypassesExistingQueueToSeedFreshSession() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffContextCustomizationEnabled = false
        }
        fixture.viewModel.state.messageQueue.enqueue("Queued after handoff", stagedContext: nil)

        try await beginAndCompleteHiddenSessionHandoff(fixture: fixture, output: "Seed immediately.")

        try await waitUntil("immediate handoff output sent before queued message") {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Seed immediately."
            ]
        }

        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after handoff"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Seed immediately."])
    }

    func testSessionHandoffCommandPromptsForSteeringAndDoesNotRetriggerWhileActive() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.triggerSessionHandoffFromCommand()
        try await waitUntil("handoff steering prompt shown") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }

        let sentMessagesBeforeSubmit = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessagesBeforeSubmit.isEmpty)

        XCTAssertTrue(fixture.viewModel.submitSessionHandoffSteeringPrompt("Focus command-triggered handoff."))
        try await waitUntil("command-triggered handoff prompt sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }

        await fixture.viewModel.startSessionHandoff(trigger: .automatic)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let hiddenPrompt = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(hiddenPrompt.hasPrefix(AppSettings.defaultSessionHandoffPrompt))
        XCTAssertTrue(hiddenPrompt.contains("## User Handoff Steering"))
        XCTAssertTrue(hiddenPrompt.hasSuffix("Focus command-triggered handoff."))
        XCTAssertEqual(sentMessages.count, 1)
    }
}

@MainActor
private func beginAndCompleteHiddenSessionHandoff(
    fixture: ConversationViewModelTestFixture,
    output: String
) async throws {
    await fixture.viewModel.startSessionHandoff(trigger: .manual)
    try await waitUntil("handoff prompt sent") {
        await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
    }

    fixture.viewModel.handleEvent(.messageChunk(text: "partial", parentToolUseId: nil))
    fixture.viewModel.handleEvent(.message(role: "assistant", content: output, parentToolUseId: nil))
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
}
