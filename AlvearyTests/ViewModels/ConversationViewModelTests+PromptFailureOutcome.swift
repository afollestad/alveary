import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testDeferredPromptAnswerFailureRestoresWaitingWithoutTerminalOutcome() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
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
        fixture.context.insert(promptRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        let registry = DefaultConversationControllerRegistry { _ in fixture.viewModel }
        let lease = registry.makeBackgroundLease(for: fixture.conversation)
        lease.activate()
        let collector = ControllerOutcomeCollector(stream: lease.outcomes())
        try await waitUntil("expected waiting outcome") { collector.values.count == 1 }

        do {
            _ = try await fixture.viewModel.answerPrompt(
                promptId: "prompt-1",
                answers: [(question: "Pick one", answer: "A")]
            )
            XCTFail("Expected deferred prompt answer to fail")
        } catch MockAgentsManager.MockError.approvalFailed {
            // expected
        }

        await Task.yield()
        XCTAssertEqual(
            collector.values.map(\.state),
            [.waitingForQuestion(interactionID: "prompt-1")]
        )
        XCTAssertNil(fixture.viewModel.state.lastControllerTerminalBoundary)
        XCTAssertEqual(
            fixture.viewModel.state.pendingToolApproval,
            PendingToolApproval(request: approval, status: .pending)
        )
    }
}
