import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveToolUseIsRejectedWhilePromptIsUnanswered() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.viewModel.state.grouper.append(event: promptRecord)

        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Write",
            toolInput: #"{"file_path":"plan.md"}"#
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        do {
            try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")
            XCTFail("Expected tool approval to be rejected while a prompt is unanswered")
        } catch {
            XCTAssertEqual(
                error as? AgentError,
                AgentError.spawnFailed("Answer the pending question before resolving tool approval")
            )
        }

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testSendIsRejectedWhilePromptIsUnanswered() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.viewModel.state.grouper.append(event: promptRecord)

        do {
            try await fixture.viewModel.send("Continue anyway")
            XCTFail("Expected send to be rejected while a prompt is unanswered")
        } catch {
            XCTAssertEqual(
                error as? AgentError,
                AgentError.spawnFailed("Answer the pending question before sending another message")
            )
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testAnswerPromptResumesDeferredAskUserQuestionInsteadOfSendingMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            conversation: conversation
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "A")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: A")
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .allow)
        XCTAssertEqual(
            approvalCalls.first?.updatedInput,
            #"{"answers":{"Pick one":"A"},"questions":[{"options":[{"description":"First","label":"A"}],"question":"Pick one"}]}"#
        )
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, nil)
    }

    func testAnswerPromptCanResolveLiveDeferredAskUserQuestion() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            conversation: conversation
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "A")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: A")
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .allow)
        XCTAssertEqual(
            approvalCalls.first?.updatedInput,
            #"{"answers":{"Pick one":"A"},"questions":[{"options":[{"description":"First","label":"A"}],"question":"Pick one"}]}"#
        )
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, nil)
    }

    func testLiveAskUserQuestionPromptSubmitIsAvailableDuringActiveTurn() throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        XCTAssertTrue(fixture.viewModel.canSubmitPromptAnswer(promptId: "prompt-1"))
    }

    func testPromptSubmitIsBlockedDuringUnrelatedActiveTurn() throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        XCTAssertFalse(fixture.viewModel.canSubmitPromptAnswer(promptId: "prompt-1"))
    }

    func testAnswerPromptDoesNotBatchSiblingToolApprovals() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let bashApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )
        let promptApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        fixture.context.insert(toolApprovalRecord(
            conversation: conversation,
            approval: bashApproval,
            timestamp: 1
        ))
        let promptRecord = askUserQuestionToolCallRecord(
            conversation: conversation,
            promptInput: promptInput,
            timestamp: 2
        )
        let promptApprovalRecord = toolApprovalRecord(
            conversation: conversation,
            approval: promptApproval,
            timestamp: 3
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(promptApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: promptApproval, status: .pending)

        _ = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "A")]
        )

        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertTrue(approvalCalls.first?.additionalApprovals.isEmpty == true)
    }

    func testAnswerPromptResumesDeferredAskUserQuestionWithCustomResponse() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            conversation: conversation
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "Something else")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: Something else")
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(approvalCalls.count, 1)
        XCTAssertEqual(approvalCalls.first?.decision, .allow)
        XCTAssertEqual(
            approvalCalls.first?.updatedInput,
            #"{"answers":{"Pick one":"Something else"},"questions":[{"options":[{"description":"First","label":"A"}],"question":"Pick one"}]}"#
        )
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, nil)
    }

    func testAnswerPromptSupersedesPendingToolApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#,
            conversation: conversation
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Write",
            toolInput: #"{"file_path":"plan.md"}"#
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.grouper.append(event: approvalRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: "prompt-1",
            answers: [(question: "Pick one", answer: "A")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: A")
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["For the question 'Pick one': A"])
        let promptItems = fixture.viewModel.state.grouper.items.compactMap { item -> PromptEntry? in
            guard case .promptBlock(_, let prompt) = item else {
                return nil
            }
            return prompt
        }
        XCTAssertEqual(promptItems.last?.submittedSummary, "Q: Pick one\nA: A")
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
    }
}

private func askUserQuestionToolCallRecord(
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

private func toolApprovalRecord(
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
