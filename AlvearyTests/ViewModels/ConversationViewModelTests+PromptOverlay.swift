import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAnswerPromptResumesDeferredAskUserQuestionAheadOfQueuedMessages() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptInput: promptInput,
            timestamp: 1
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = overlayToolApprovalRecord(
            conversation: conversation,
            approval: approval,
            timestamp: 2
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        fixture.viewModel.state.messageQueue.enqueue("Older queued message", stagedContext: "Queued context")

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "A")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: A")
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Older queued message"])
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.first?.stagedContext, "Queued context")
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .allow)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testDismissPromptDeniesDeferredAskUserQuestionAndHidesPrompt() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptInput: promptInput,
            timestamp: 1
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = overlayToolApprovalRecord(
            conversation: conversation,
            approval: approval,
            timestamp: 2
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .deny)
        XCTAssertNil(approvalCalls.first?.updatedInput)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
        XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.visibleTranscriptItems.isEmpty)
        XCTAssertFalse(try promptOverlayRecords(in: fixture).contains {
            $0.type == "stop" && $0.content == ConversationInterruption.displayMessage
        })
    }

    func testDismissPromptDeniesLiveAskUserQuestionAndEndsTurn() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptInput: promptInput,
            timestamp: 1
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = overlayToolApprovalRecord(
            conversation: conversation,
            approval: approval,
            timestamp: 2
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .deny)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
        XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertFalse(try promptOverlayRecords(in: fixture).contains {
            $0.type == "stop" && $0.content == ConversationInterruption.displayMessage
        })
    }

    func testDismissPromptWithoutApprovalCancelsActiveTurnAndHidesPrompt() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            timestamp: 1
        )
        fixture.context.insert(promptRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: promptRecord)

        try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")

        let cancelCalls = await fixture.agentsManager.cancelCalls()
        XCTAssertEqual(cancelCalls, [conversation.id])
        XCTAssertEqual(promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(approvalCalls.isEmpty)
        XCTAssertFalse(try promptOverlayRecords(in: fixture).contains {
            $0.type == "stop" && $0.content == ConversationInterruption.displayMessage
        })
    }

    func testDismissPromptSuppressesLateCancelledTurnFalloutAndLeavesQueuedMessagesQueued() async throws {
        let fixture = try await dismissedOverlayPromptFixture(queuedMessage: "Queued after prompt")

        emitLateCancelledPromptFallout(in: fixture)

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(fixture.viewModel.state.messageQueue.pending.map(\.text), ["Queued after prompt"])
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertNil(fixture.viewModel.state.lastTurnError)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(try promptOverlayRecords(in: fixture).contains {
            $0.type == "tokens" || $0.type == "error" || $0.type == "stop" || $0.toolName == "ExitPlanMode"
        })
    }

    func testDismissPromptThenNewMessageSendsNormally() async throws {
        let fixture = try await dismissedOverlayPromptFixture()

        try await fixture.viewModel.queueOrSend("Continue after dismiss")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Continue after dismiss"])
        XCTAssertNil(fixture.viewModel.state.messageQueue.peekNext())
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Continue after dismiss"])
    }

    func testDismissPromptSuppressesProviderFallbackBeforeResolutionReturns() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let seededPrompt = try seedOverlayPromptApproval(in: fixture, promptInput: promptInput)
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: seededPrompt.promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: seededPrompt.approval, status: .pending)
        await fixture.agentsManager.pauseApprovalResolution()

        let dismissTask = Task { @MainActor in
            try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")
        }
        defer { dismissTask.cancel() }
        try await waitUntil("expected dismiss to pause during provider resolution") {
            await fixture.agentsManager.isApprovalResolutionPaused()
        }

        fixture.viewModel.handleEvent(.messageChunk(text: "Permission denied. ", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "Permission denied. Plan mode test blocked at AskUserQuestion. Nothing written.",
            parentToolUseId: nil
        ))
        fixture.viewModel.handleEvent(.toolCall(
            id: "plan-exit-1",
            name: "ExitPlanMode",
            input: "{}",
            parentToolUseId: nil,
            callerAgent: nil
        ))
        fixture.viewModel.handleEvent(.toolApprovalRequested(ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "plan-exit-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )))
        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))
        await fixture.agentsManager.resumeApprovalResolution()
        try await dismissTask.value

        XCTAssertNil(fixture.viewModel.state.streamingText)
        XCTAssertNil(fixture.viewModel.state.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertFalse(try promptOverlayRecords(in: fixture).contains {
            ($0.type == "message" && $0.content?.contains("Permission denied") == true) ||
                ($0.type == "stop" && $0.content == ConversationInterruption.displayMessage) ||
                $0.toolName == "ExitPlanMode"
        })
    }

    func testDismissPromptIgnoresLateMatchingApprovalRequest() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let seededPrompt = try seedOverlayPromptApproval(in: fixture, promptInput: promptInput)
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: seededPrompt.promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: seededPrompt.approval, status: .pending)

        try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")
        fixture.viewModel.handleEvent(.toolApprovalRequested(seededPrompt.approval))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
        XCTAssertEqual(seededPrompt.promptRecord.content, ChatItemGrouper.handledPromptSummary)
    }

    func testNormalCancelStillRendersInterruptedCue() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        fixture.viewModel.state.turnState.beginTurn()

        await fixture.viewModel.cancel()
        fixture.viewModel.handleEvent(.tokens(
            input: 0,
            output: 0,
            cacheRead: 0,
            isError: true,
            stopReason: "cancelled",
            durationMs: 1,
            costUsd: nil,
            permissionDenials: []
        ))

        XCTAssertTrue(try promptOverlayRecords(in: fixture).contains {
            $0.type == "stop" && $0.content == ConversationInterruption.displayMessage
        })
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
    }
}

@MainActor
private func promptOverlayRecords(in fixture: ConversationViewModelTestFixture) throws -> [ConversationEventRecord] {
    try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
        $0.conversationId == fixture.conversation.id
    }
}

@MainActor
private func dismissedOverlayPromptFixture(
    queuedMessage: String? = nil
) async throws -> ConversationViewModelTestFixture {
    let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
    let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
    let seededPrompt = try seedOverlayPromptApproval(in: fixture, promptInput: promptInput)
    fixture.viewModel.state.turnState.beginTurn()
    fixture.viewModel.state.grouper.append(event: seededPrompt.promptRecord)
    fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: seededPrompt.approval, status: .pending)
    if let queuedMessage {
        fixture.viewModel.state.messageQueue.enqueue(queuedMessage, stagedContext: nil)
    }

    try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")
    return fixture
}

@MainActor
private func emitLateCancelledPromptFallout(in fixture: ConversationViewModelTestFixture) {
    fixture.viewModel.handleEvent(.tokens(
        input: 0,
        output: 0,
        cacheRead: 0,
        isError: false,
        stopReason: nil,
        durationMs: 1,
        costUsd: nil,
        permissionDenials: [PermissionDenialSummary(toolName: "AskUserQuestion", toolUseId: "prompt-1")]
    ))
    fixture.viewModel.handleEvent(.tokens(
        input: 1,
        output: 1,
        cacheRead: 0,
        isError: false,
        stopReason: "end_turn",
        durationMs: 2,
        costUsd: nil,
        permissionDenials: []
    ))
    fixture.viewModel.handleEvent(.toolCall(
        id: "plan-exit-1",
        name: "ExitPlanMode",
        input: "{}",
        parentToolUseId: nil,
        callerAgent: nil
    ))
    fixture.viewModel.handleEvent(.toolApprovalRequested(ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: "plan-exit-1",
        toolName: "ExitPlanMode",
        toolInput: "{}"
    )))
    fixture.viewModel.handleEvent(.tokens(
        input: 0,
        output: 0,
        cacheRead: 0,
        isError: false,
        stopReason: "tool_deferred",
        durationMs: 3,
        costUsd: nil,
        permissionDenials: []
    ))
    fixture.viewModel.handleEvent(.error(message: "No active turn to cancel"))
    fixture.viewModel.handleEvent(.stop(message: nil))
}

@MainActor
private func seedOverlayPromptApproval(
    in fixture: ConversationViewModelTestFixture,
    promptInput: String
) throws -> (promptRecord: ConversationEventRecord, approval: ToolApprovalRequest) {
    let conversation = try fixture.dbConversation()
    let promptRecord = overlayAskUserQuestionToolCallRecord(
        conversation: conversation,
        promptInput: promptInput,
        timestamp: 1
    )
    let approval = ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: "prompt-1",
        toolName: "AskUserQuestion",
        toolInput: promptInput
    )
    fixture.context.insert(promptRecord)
    fixture.context.insert(overlayToolApprovalRecord(
        conversation: conversation,
        approval: approval,
        timestamp: 2
    ))
    try fixture.context.save()
    return (promptRecord, approval)
}

private func overlayAskUserQuestionToolCallRecord(
    conversation: Conversation,
    promptInput: String,
    timestamp: TimeInterval
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_call",
        toolId: "prompt-1",
        toolName: "AskUserQuestion",
        toolInput: promptInput,
        timestamp: Date(timeIntervalSince1970: timestamp),
        conversation: conversation
    )
}

private func overlayToolApprovalRecord(
    conversation: Conversation,
    approval: ToolApprovalRequest,
    timestamp: TimeInterval
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: approval.sessionId,
        toolId: approval.toolUseId,
        toolName: approval.toolName,
        toolInput: approval.toolInput,
        timestamp: Date(timeIntervalSince1970: timestamp),
        conversation: conversation
    )
}
