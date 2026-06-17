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
}
