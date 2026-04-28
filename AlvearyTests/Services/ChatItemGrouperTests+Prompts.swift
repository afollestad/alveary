import XCTest

@testable import Alveary

extension ChatItemGrouperTests {
    func testPromptToolResultIsSuppressedAndMarkPromptAnsweredPatchesPrompt() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let promptCall = ConversationEventRecord(
            id: "prompt-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: "{\"questions\":[{\"question\":\"Pick one\",\"options\":[{\"label\":\"A\",\"description\":\"First\"}]}]}"
        )
        let suppressedResult = ConversationEventRecord(
            id: "prompt-result",
            conversationId: conversationId,
            type: "tool_result",
            toolId: "prompt-1",
            toolOutput: "Answer questions?",
            isError: true
        )

        grouper.update(events: [promptCall, suppressedResult])
        grouper.markPromptAnswered(promptId: "prompt-1", summary: "A")

        XCTAssertEqual(grouper.items.count, 1)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected a prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertEqual(prompt.questions.first?.question, "Pick one")
        XCTAssertEqual(prompt.submittedSummary, "A")
    }

    func testNewPromptReplacesUnansweredPromptAndDropsRetryChatter() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let firstPrompt = ConversationEventRecord(
            id: "prompt-call-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"First?","options":[{"label":"A","description":"First"}]}]}"#
        )
        let retryMessage = ConversationEventRecord(
            id: "retry-message",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "I'll retry the question."
        )
        let secondPrompt = ConversationEventRecord(
            id: "prompt-call-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-2",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Second?","options":[{"label":"B","description":"Second"}]}]}"#
        )

        grouper.update(events: [firstPrompt, retryMessage, secondPrompt])

        XCTAssertEqual(grouper.items.count, 1)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected the latest prompt to replace the unanswered one")
        }
        XCTAssertEqual(prompt.id, "prompt-2")
        XCTAssertEqual(prompt.questions.first?.question, "Second?")
        XCTAssertNil(prompt.submittedSummary)
    }

    func testAssistantContinuationMarksUnansweredPromptHandledSoLaterApprovalIsActionable() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let prompt = ConversationEventRecord(
            id: "prompt-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        let continuation = ConversationEventRecord(
            id: "assistant-continued",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "The user declined the question. I'll continue."
        )
        let approval = ConversationEventRecord(
            id: "approval-1",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-1",
            toolId: "write-1",
            toolName: "Write",
            toolInput: #"{"file_path":"plan.md"}"#
        )

        grouper.update(events: [prompt, continuation, approval])

        XCTAssertFalse(grouper.hasUnansweredPrompt)
        guard case .promptBlock(_, let renderedPrompt) = grouper.items.first else {
            return XCTFail("Expected the prompt to remain visible")
        }
        XCTAssertEqual(renderedPrompt.submittedSummary, ChatItemGrouper.handledPromptSummary)
        XCTAssertTrue(grouper.items.contains { item in
            if case .toolApproval(_, let request, nil) = item {
                return request.toolUseId == "write-1"
            }
            return false
        })
    }

    func testParallelApprovalDoesNotMarkUnansweredPromptHandledWithoutContinuation() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let prompt = ConversationEventRecord(
            id: "prompt-call",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        let approval = ConversationEventRecord(
            id: "approval-1",
            conversationId: conversationId,
            type: "tool_approval",
            content: "session-1",
            toolId: "write-1",
            toolName: "Write",
            toolInput: #"{"file_path":"plan.md"}"#
        )

        grouper.update(events: [prompt, approval])

        XCTAssertTrue(grouper.hasUnansweredPrompt)
        guard case .promptBlock(_, let renderedPrompt) = grouper.items.first else {
            return XCTFail("Expected the prompt to remain visible")
        }
        XCTAssertNil(renderedPrompt.submittedSummary)
    }

    func testAskUserQuestionDefaultsToAllowingCustomResponse() {
        let grouper = ChatItemGrouper()

        let questions = grouper.parseAskUserQuestionInput(
            #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )

        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?.renderedOptions.last?.label, "Other")
        XCTAssertEqual(questions.first?.renderedOptions.last?.isCustomResponse, true)
    }

    func testAskUserQuestionCanDisableCustomResponse() {
        let grouper = ChatItemGrouper()

        let questions = grouper.parseAskUserQuestionInput(
            #"{"questions":[{"question":"Pick one","allowCustomResponse":false,"options":[{"label":"A","description":"First"}]}]}"#
        )

        XCTAssertEqual(questions.count, 1)
        XCTAssertFalse(questions.first?.renderedOptions.contains(where: { $0.isCustomResponse }) ?? true)
    }

    func testReplayedAnsweredPromptWithSameToolIdDoesNotAppendDuplicateBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let promptCall = ConversationEventRecord(
            id: "prompt-call-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        let assistantMessage = ConversationEventRecord(
            id: "assistant-1",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "I've entered plan mode and posed a question."
        )
        let replayedPromptCall = ConversationEventRecord(
            id: "prompt-call-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )

        grouper.append(event: promptCall)
        grouper.markPromptAnswered(promptId: "prompt-1", summary: "Q: Pick one\nA: A")
        grouper.append(event: assistantMessage)
        grouper.append(event: replayedPromptCall)

        XCTAssertEqual(grouper.items.count, 2)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected the original prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertEqual(prompt.submittedSummary, "Q: Pick one\nA: A")
        guard case .assistantMessage(_, let text) = grouper.items[1] else {
            return XCTFail("Expected the assistant message to remain after the prompt")
        }
        XCTAssertEqual(text, "I've entered plan mode and posed a question.")
    }

    func testReplayedAnsweredPromptWithDifferentToolIdButSameQuestionsDoesNotAppendDuplicateBlock() {
        let grouper = ChatItemGrouper()
        let conversationId = "conversation-1"
        let promptCall = ConversationEventRecord(
            id: "prompt-call-1",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        let assistantMessage = ConversationEventRecord(
            id: "assistant-1",
            conversationId: conversationId,
            type: "message",
            role: "assistant",
            content: "I've entered plan mode and posed a question."
        )
        let replayedPromptCall = ConversationEventRecord(
            id: "prompt-call-2",
            conversationId: conversationId,
            type: "tool_call",
            toolId: "prompt-2",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )

        grouper.append(event: promptCall)
        grouper.markPromptAnswered(promptId: "prompt-1", summary: "Q: Pick one\nA: A")
        grouper.append(event: assistantMessage)
        grouper.append(event: replayedPromptCall)

        XCTAssertEqual(grouper.items.count, 2)
        guard case .promptBlock(_, let prompt) = grouper.items[0] else {
            return XCTFail("Expected the original prompt block")
        }
        XCTAssertEqual(prompt.id, "prompt-1")
        XCTAssertEqual(prompt.submittedSummary, "Q: Pick one\nA: A")
        guard case .assistantMessage(_, let text) = grouper.items[1] else {
            return XCTFail("Expected the assistant message to remain after the prompt")
        }
        XCTAssertEqual(text, "I've entered plan mode and posed a question.")
    }
}
