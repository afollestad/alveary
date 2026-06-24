import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
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
        fixture.viewModel.handleEvent(.runtimeActivity(state: .active, turnId: "turn-2", outcome: .unknown))
        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Fresh answer", parentToolUseId: nil))
        XCTAssertTrue(try promptOverlayRecords(in: fixture).contains { $0.type == "message" && $0.content == "Fresh answer" })
    }

    func testDismissPromptAllowsReplacementActivityBeforeVisibleTurnIsFullyMarked() async throws {
        let fixture = try await dismissedOverlayPromptFixture()
        let model = fixture.viewModel
        model.state.lastTurnInterrupted = false
        XCTAssertTrue(model.markPromptDismissalNewOutboundTurnStarted())
        model.handleEvent(.runtimeActivity(state: .active, turnId: "turn-2", outcome: .unknown))
        model.handleEvent(.message(role: "assistant", content: "Fresh answer", parentToolUseId: nil))
        XCTAssertTrue(try promptOverlayRecords(in: fixture).contains { $0.type == "message" && $0.content == "Fresh answer" })
    }

    func testAnswerReplacementPromptAfterDismissAllowsResponseWithoutRuntimeActivity() async throws {
        let fixture = try await dismissedOverlayPromptFixture()
        let model = fixture.viewModel
        try await model.queueOrSend("Ask questions again")
        let conversation = try fixture.dbConversation()
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let promptRecord = overlayAskUserQuestionToolCallRecord(
            conversation: conversation,
            promptId: "prompt-2",
            promptInput: promptInput,
            timestamp: 10
        )
        let approval = ToolApprovalRequest(sessionId: "session-123", toolUseId: "prompt-2", toolName: "AskUserQuestion", toolInput: promptInput)
        let approvalRecord = overlayToolApprovalRecord(conversation: conversation, approval: approval, timestamp: 11)
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        model.state.grouper.append(event: promptRecord)
        model.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        _ = try await model.answerPrompt(promptId: "prompt-2", answers: [(question: "Pick one", answer: "A")])
        model.handleEvent(.message(role: "assistant", content: "Fresh proposal", parentToolUseId: nil))

        XCTAssertTrue(try promptOverlayRecords(in: fixture).contains { $0.type == "message" && $0.content == "Fresh proposal" })
    }

    func testDismissPromptThenFreshPromptWithoutRuntimeActivityStaysActionable() async throws {
        let fixture = try await dismissedOverlayPromptFixture()
        let model = fixture.viewModel

        try await model.queueOrSend("Again")
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let freshApproval = ToolApprovalRequest(
            sessionId: "session-new",
            toolUseId: "prompt-2",
            toolName: "AskUserQuestion",
            toolInput: promptInput
        )
        model.handleEvent(.toolApprovalRequested(freshApproval))
        model.handleEvent(.toolCall(
            id: "prompt-2",
            name: "AskUserQuestion",
            input: promptInput,
            parentToolUseId: nil,
            callerAgent: nil
        ))
        try await Task.sleep(for: .milliseconds(50))

        let sentMessages = await fixture.agentsManager.sentMessages()
        let approvalToolUseIds = await fixture.agentsManager.approvalCalls().map(\.approval.toolUseId)
        XCTAssertEqual(sentMessages, ["Again"])
        XCTAssertEqual(approvalToolUseIds, ["prompt-1"])
        XCTAssertEqual(model.state.pendingToolApproval?.request, freshApproval)
        XCTAssertTrue(model.hasUnansweredPrompt)
        XCTAssertFalse(model.promptDismissalFalloutSuppressionActive)
        XCTAssertNil(model.lastTurnError)
    }

    func testDismissPromptThenLateMatchingPromptAfterNextSendStaysSuppressed() async throws {
        let fixture = try await dismissedOverlayPromptFixture()
        let model = fixture.viewModel

        try await model.queueOrSend("Again")
        let staleApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "prompt-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        )
        model.handleEvent(.toolApprovalRequested(staleApproval))
        model.handleEvent(.toolCall(
            id: "prompt-1",
            name: "AskUserQuestion",
            input: staleApproval.toolInput,
            parentToolUseId: nil,
            callerAgent: nil
        ))
        model.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 2,
            costUsd: nil,
            permissionDenials: [],
            isTerminal: true
        ))
        try await Task.sleep(for: .milliseconds(50))

        let sentMessages = await fixture.agentsManager.sentMessages()
        let approvalToolUseIds = await fixture.agentsManager.approvalCalls().map(\.approval.toolUseId)
        XCTAssertEqual(sentMessages, ["Again"])
        XCTAssertEqual(approvalToolUseIds, ["prompt-1"])
        XCTAssertNil(model.state.pendingToolApproval)
        XCTAssertFalse(model.hasUnansweredPrompt)
        XCTAssertFalse(model.promptDismissalFalloutSuppressionActive)
        let matchingPromptToolCalls = try promptOverlayRecords(in: fixture).filter {
            $0.toolId == "prompt-1" && $0.type == "tool_call"
        }
        XCTAssertEqual(matchingPromptToolCalls.count, 1)
        XCTAssertEqual(matchingPromptToolCalls.first?.content, ChatItemGrouper.handledPromptSummary)
    }

    func testDismissPromptThenFreshCompletionWithoutRuntimeActivityEndsTurn() async throws {
        let fixture = try await dismissedOverlayPromptFixture()
        let model = fixture.viewModel

        try await model.queueOrSend("Again")
        model.handleEvent(.message(role: "assistant", content: "Fresh answer", parentToolUseId: nil))
        model.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 2,
            costUsd: nil,
            permissionDenials: [],
            isTerminal: true
        ))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Again"])
        XCTAssertFalse(model.turnState.isActive)
        XCTAssertFalse(model.promptDismissalFalloutSuppressionActive)
        XCTAssertTrue(try promptOverlayRecords(in: fixture).contains {
            $0.type == "message" && $0.content == "Fresh answer"
        })
    }
}
