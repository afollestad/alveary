import AgentCLIKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testOpenCodeTerminalBeforeSubmissionReturnsKeepsConversationIdle() async throws {
        for message in ["Quick answer", "/compact"] {
            let fixture = try await openCodeEarlyCompletionFixture()

            try await fixture.viewModel.send(message)

            XCTAssertFalse(fixture.viewModel.turnState.isActive)
            XCTAssertEqual(fixture.viewModel.state.lastControllerTerminalBoundary?.result, .succeeded)
            XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
            XCTAssertEqual(try fixture.userMessages().map(\.content), [message])
        }
    }

    func testOpenCodeSteeringTerminalBeforeSubmissionReturnsKeepsConversationIdle() async throws {
        let fixture = try await openCodeEarlyCompletionFixture()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.steer("Quick steering")

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
        let steering = await fixture.agentsManager.steeringCalls()
        XCTAssertEqual(steering.count, 1)
    }

    func testOpenCodeTerminalFailureBeforeSubmissionReturnsPreservesFailure() async throws {
        let fixture = try await openCodeEarlyCompletionFixture(terminalFailure: true)

        try await fixture.viewModel.send("Accepted prompt")

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
        guard case .failed = fixture.viewModel.state.lastControllerTerminalBoundary?.result else {
            return XCTFail("Expected the terminal model failure to remain recorded")
        }
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
    }

    func testOpenCodeHiddenHandoffFailureBeforeSubmissionReturnsStaysIdle() async throws {
        let fixture = try await openCodeEarlyCompletionFixture(terminalFailure: true)

        await fixture.viewModel.startHiddenSessionHandoff()

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertNotNil(fixture.viewModel.state.failedSessionHandoffMessage)
    }

    func testOpenCodeInlineCompletionStartsHandoffBeforeQueuedWork() async throws {
        let fixture = try await openCodeEarlyCompletionFixture(contextInput: 190, queuedDuringSubmission: "After handoff")
        fixture.settingsService.update { $0.sessionHandoffWindowPercentage = 85 }
        fixture.viewModel.activateViewLifecycle()
        defer { fixture.viewModel.deactivateViewLifecycle() }

        try await fixture.viewModel.send("Complete the current turn")

        try await waitUntil("Inline OpenCode completion starts automatic handoff") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Complete the current turn"])
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["After handoff"])
    }

    func testOpenCodeAmbiguousSubmissionPreservesTerminalFailureWithoutReplay() async throws {
        let fixture = try await openCodeEarlyCompletionFixture(terminalFailure: true)
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        do {
            try await fixture.viewModel.send("Possibly accepted prompt")
            XCTFail("Expected the submission error")
        } catch {
            XCTAssertEqual(error as? MockAgentsManager.MockError, .sendFailed)
        }

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
        guard case .failed = fixture.viewModel.state.lastControllerTerminalBoundary?.result else {
            return XCTFail("Submission rollback must preserve its terminal failure")
        }
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertEqual(try fixture.userMessages().count, 1)
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageIDs.count, 1)
    }

    func testOpenCodeFailedSubmissionCannotStartDeferredAutomaticHandoff() async throws {
        let fixture = try await openCodeEarlyCompletionFixture(contextInput: 190)
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))
        do {
            try await fixture.viewModel.send("Unconfirmed prompt")
            XCTFail("Expected the submission error")
        } catch {
            XCTAssertEqual(error as? MockAgentsManager.MockError, .sendFailed)
        }

        try await waitUntil("Failed OpenCode submission clears deferred handoff") {
            !fixture.viewModel.state.isAutomaticSessionHandoffPending
        }
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    func testOpenCodeQueueDrainsWhenSubmissionsCompleteBeforeReturning() async throws {
        let fixture = try await openCodeEarlyCompletionFixture()
        fixture.viewModel.state.messageQueue.enqueue("First queued")
        fixture.viewModel.state.messageQueue.enqueue("Second queued")
        fixture.viewModel.activateViewLifecycle()
        defer { fixture.viewModel.deactivateViewLifecycle() }

        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("OpenCode inline terminal completions drain queue") {
            await fixture.agentsManager.sentMessages().count == 2
        }
        try await waitUntil("OpenCode queue drain finishes") {
            fixture.viewModel.queueDrainTask == nil
        }
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.messageQueue.pending.isEmpty)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["First queued", "Second queued"])
        XCTAssertEqual(Set(try fixture.userMessages().compactMap(\.content)), ["First queued", "Second queued"])
    }

    private func openCodeEarlyCompletionFixture(
        terminalFailure: Bool = false, contextInput: Int? = nil, queuedDuringSubmission: String? = nil
    ) async throws -> ConversationViewModelTestFixture {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        fixture.thread.effort = AppSettings.openCodeDefaultEffort
        fixture.thread.permissionMode = "ask"
        fixture.viewModel.state.liveSessionConfig = try fixture.viewModel.makeSpawnConfig()
        let viewModel = fixture.viewModel
        await fixture.agentsManager.setSendEpilogue { [weak viewModel] in
            if let queuedDuringSubmission { viewModel?.state.messageQueue.enqueue(queuedDuringSubmission) }
            if let contextInput {
                viewModel?.handleEvent(.tokens(
                    input: contextInput, output: 0, cacheRead: 0, isError: false, stopReason: ConversationEvent.interimUsageStopReason,
                    durationMs: 0, costUsd: nil, contextWindowSize: 200, permissionDenials: []
                ))
            }
            viewModel?.handleEvent(.tokens(
                input: 0, output: 0, cacheRead: 0, isError: terminalFailure, stopReason: terminalFailure ? "error" : "end_turn",
                durationMs: 0, costUsd: nil, permissionDenials: [], isTerminal: true
            ))
            viewModel?.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))
        }
        return fixture
    }

    func testRestoredOpenCodeApprovalUsesNativeBindingBeforeGlobalDefault() throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        let conversation = try fixture.dbConversation()
        conversation.harness = nil
        conversation.harnessSessionHarnessId = "opencode"
        conversation.harnessSessionId = "ses_native"
        fixture.settingsService.update { $0.defaultHarness = "claude" }
        let approval = ToolApprovalRequest(
            sessionId: "ses_native", toolUseId: "per_native", toolName: "Bash", toolInput: #"{"command":"pwd"}"#
        )

        fixture.viewModel.restoreToolApproval(approval)

        XCTAssertEqual(fixture.viewModel.toolApprovalHarnessId(), "opencode")
        XCTAssertFalse(fixture.viewModel.state.isRestoringToolApproval)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
        let snapshot = fixture.viewModel.exitPlanModeRevisionHarnessSnapshot()
        XCTAssertEqual(snapshot.harnessId, "opencode")
        XCTAssertEqual(snapshot.harnessSessionId, "ses_native")
    }

    func testOpenCodeClosedMultiSelectAndRepeatedQuestionsKeepIndexedAnswerArrays() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false, harnessId: "opencode")
        fixture.thread.effort = AppSettings.openCodeDefaultEffort
        fixture.thread.permissionMode = "ask"
        let conversation = try fixture.dbConversation()
        let promptInput = """
        {"questions":[
          {"question":"Choose","custom":false,"multiSelect":true,"options":[{"label":"Alpha, Beta"},{"label":"Gamma"}]},
          {"question":"Choose","custom":false,"options":[{"label":"Gamma"}]}]}
        """
        let requestID = "que_native_multi"
        let approval = ToolApprovalRequest(
            sessionId: "ses_native", toolUseId: requestID, toolName: "AskUserQuestion", toolInput: promptInput
        )
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id, type: "tool_call", toolId: requestID, toolName: "AskUserQuestion",
            toolInput: promptInput, timestamp: Date(timeIntervalSince1970: 1), conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(ConversationEventRecord(
            conversationId: conversation.id, type: "tool_approval", content: "ses_native", toolId: requestID,
            toolName: "AskUserQuestion", toolInput: promptInput, toolApprovalStatus: ToolApprovalStatus.pending.rawValue,
            timestamp: Date(timeIntervalSince1970: 2), conversation: conversation
        ))
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        let prompt = try XCTUnwrap(fixture.viewModel.state.grouper.latestUnansweredPrompt)
        var overlay = AskUserQuestionOverlayState()
        overlay.selections = [0: ["Alpha, Beta", "Gamma"], 1: ["Gamma"]]

        _ = try await fixture.viewModel.answerPrompt(
            promptId: requestID, answers: overlay.answers(for: prompt), answerSelections: overlay.answerSelections(for: prompt)
        )

        let calls = await fixture.agentsManager.approvalCalls()
        let updatedInput = try XCTUnwrap(calls.first?.updatedInput)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(updatedInput.utf8)) as? [String: Any])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(updated["answers"] as? [String: [String]], ["0": ["Alpha, Beta", "Gamma"], "1": ["Gamma"]])
        let sent = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sent.isEmpty)
    }

    func testOpenCodeApprovalBatchUsesOnlyRealPermissionIDs() throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        let conversation = try fixture.dbConversation()
        for (index, id) in ["tool-native", "per_first", "per_second"].enumerated() {
            fixture.context.insert(ConversationEventRecord(
                conversationId: conversation.id, type: index == 0 ? "tool_call" : "tool_approval",
                content: index == 0 ? nil : "ses_native", toolId: id, toolName: "Bash", toolInput: #"{"command":"git status"}"#,
                timestamp: Date(timeIntervalSince1970: Double(index)), conversation: conversation
            ))
        }
        try fixture.context.save()
        let approval = ToolApprovalRequest(
            sessionId: "ses_native", toolUseId: "per_first", toolName: "Bash", toolInput: #"{"command":"git status"}"#
        )
        let related = fixture.viewModel.relatedDeferredToolApprovals(for: approval)
        XCTAssertEqual(related.map(\.toolUseId), ["per_second"])

        conversation.harness = nil
        conversation.harnessSessionHarnessId = "opencode"
        fixture.settingsService.update { $0.defaultHarness = "claude" }
        let restored = fixture.viewModel.relatedDeferredToolApprovals(for: approval)
        XCTAssertEqual(restored.map(\.toolUseId), ["per_second"])
    }

    func testOpenCodeAdditiveCacheThresholdWaitsForRootTurnCompletion() async throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        fixture.conversation.harness = nil
        fixture.conversation.harnessSessionHarnessId = "opencode"
        fixture.settingsService.update { $0.defaultHarness = "codex" }
        fixture.settingsService.update { $0.sessionHandoffWindowPercentage = 85 }
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: ToolApprovalRequest(
            sessionId: "ses_native", toolUseId: "per_native", toolName: "Bash", toolInput: #"{"command":"pwd"}"#
        ), status: .pending)
        applyOpenCodeUsage(AgentUsageEvent(
            model: "provider/model", inputTokens: 20, outputTokens: 5, cacheReadInputTokens: 150, cacheCreationInputTokens: 10,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        ), to: fixture)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)

        fixture.viewModel.state.pendingToolApproval = nil
        applyOpenCodeUsage(AgentUsageEvent(
            model: nil, inputTokens: nil, outputTokens: nil, stopReason: "end_turn", isTerminal: true
        ), to: fixture)

        try await waitUntil("OpenCode terminal boundary starts automatic handoff") {
            fixture.viewModel.state.isAwaitingHandoffSteering
        }
        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
    }

    func testOpenCodeTerminalUsagePreservesMeasuredContextAndDurableCompletion() throws {
        for failed in [false, true] {
            let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
            fixture.viewModel.state.turnState.beginTurn()
            applyOpenCodeUsage(AgentUsageEvent(
                model: "provider/model", inputTokens: 20, outputTokens: 5, cacheReadInputTokens: 70, cacheCreationInputTokens: 10,
                costUSD: 0.25, contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
            ), to: fixture)
            if failed {
                fixture.viewModel.handleEvent(.contextCompactionStarted(id: "compact", trigger: "manual"))
                fixture.viewModel.handleEvent(.contextCompactionFailed(id: "compact", error: "Compaction was interrupted."))
            }
            applyOpenCodeUsage(AgentUsageEvent(
                model: nil, inputTokens: nil, outputTokens: nil,
                stopReason: failed ? "error" : "end_turn", isTerminal: true, isError: failed
            ), to: fixture)

            let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>(sortBy: [SortDescriptor(\.timestamp)]))
            let summary = try XCTUnwrap(ConversationUsageSummary.derive(
                from: records, cachedContextWindowSize: nil, harnessID: "opencode"
            ))
            XCTAssertEqual(summary.contextUsedTokens, 100)
            XCTAssertEqual(summary.contextUsagePercent, 50)
            XCTAssertEqual(summary.totalCostUsd, 0.25)
            XCTAssertTrue(records.contains { $0.type == "tokens" && $0.stopReason == (failed ? "error" : "end_turn") })
            XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        }
    }

    func testOpenCodeCompactionUpdatesHandoffThresholdBeforeTerminalBoundary() async throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        fixture.viewModel.state.turnState.beginTurn()
        applyOpenCodeUsage(AgentUsageEvent(
            model: "provider/model", inputTokens: 190, outputTokens: 5,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        ), to: fixture)
        fixture.viewModel.handleEvent(.contextCompactionStarted(id: "compact", trigger: "auto"))
        fixture.viewModel.handleEvent(.contextCompactionCompleted(id: "compact", summary: nil))
        applyOpenCodeUsage(AgentUsageEvent(
            model: "provider/model", inputTokens: 50, outputTokens: 5,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        ), to: fixture)
        applyOpenCodeUsage(AgentUsageEvent(
            model: nil, inputTokens: nil, outputTokens: nil, stopReason: "end_turn", isTerminal: true
        ), to: fixture)
        await Task.yield()
        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testOpenCodeManualCompactionDoesNotHandoffFromSummaryInputUsage() async throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.handleEvent(.contextCompactionStarted(id: "compact", trigger: "manual"))
        applyOpenCodeUsage(AgentUsageEvent(
            model: "provider/model", inputTokens: 190, outputTokens: 20,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        ), to: fixture)
        fixture.viewModel.handleEvent(.contextCompactionCompleted(id: "compact", summary: "Summary"))
        applyOpenCodeUsage(AgentUsageEvent(
            model: nil, inputTokens: nil, outputTokens: nil, stopReason: "end_turn", isTerminal: true
        ), to: fixture)
        await Task.yield()
        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testOpenCodeCancellationKeepsUsageWithoutStartingAutomaticHandoff() async throws {
        let fixture = try ConversationViewModelTestFixture(harnessId: "opencode")
        fixture.viewModel.state.turnState.beginTurn()
        applyOpenCodeUsage(AgentUsageEvent(
            model: "provider/model", inputTokens: 190, outputTokens: 5,
            contextWindow: 200, stopReason: AgentUsageEvent.interimUsageStopReason
        ), to: fixture)
        await fixture.viewModel.cancel()
        XCTAssertTrue(fixture.viewModel.state.isCancellingTurn)
        applyOpenCodeUsage(AgentUsageEvent(
            model: nil, inputTokens: nil, outputTokens: nil, stopReason: "end_turn", isTerminal: true
        ), to: fixture)
        await Task.yield()
        XCTAssertFalse(fixture.viewModel.state.isAutomaticSessionHandoffPending)
        XCTAssertFalse(fixture.viewModel.state.isAwaitingHandoffSteering)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>(sortBy: [SortDescriptor(\.timestamp)]))
        XCTAssertTrue(records.contains { $0.type == "stop" && $0.content == ConversationInterruption.displayMessage })
        XCTAssertEqual(ConversationUsageSummary.derive(
            from: records, cachedContextWindowSize: nil, harnessID: "opencode"
        )?.contextUsedTokens, 190)
    }
}

@MainActor
private func applyOpenCodeUsage(_ usage: AgentUsageEvent, to fixture: ConversationViewModelTestFixture) {
    let envelope = AgentEventEnvelope(
        generation: 1, index: 0, harnessId: .opencode, conversationId: AgentConversationID(rawValue: fixture.conversation.id),
        harnessSessionId: nil, source: .stdout, event: .usage(usage)
    )
    for event in AgentCLIKitEventMapper().conversationEvents(from: envelope) {
        fixture.viewModel.handleEvent(event)
    }
}
