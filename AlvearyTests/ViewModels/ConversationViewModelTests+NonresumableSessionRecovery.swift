import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testQueuedMessageRecoveryFailureKeepsLocalContextForRetry() async throws {
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.state.stagedContext = "Queued context"
        fixture.viewModel.turnState.beginTurn()
        try seedLocalRestoreHistory(
            fixture,
            userMessage: "Summarize index.html.",
            assistantMessage: "The file contains a portfolio home page."
        )

        try await fixture.viewModel.queueOrSend("Queued follow-up")
        await fixture.agentsManager.enqueueSpawnError(
            CodexAppServerError.jsonRPCError(
                method: "thread/resume",
                code: -32600,
                message: "no rollout found for thread id 019ee845-0b26-7061-af79-9bd2327f8401"
            )
        )
        await fixture.agentsManager.enqueueOutboundReadiness(.respawnRequired)
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued recovery failure recorded on transcript message") {
            let userMessages = try fixture.userMessages()
            guard let userMessage = userMessages.first(where: { $0.content == "Queued follow-up" }) else {
                return false
            }
            return fixture.viewModel.messageQueue.peekNext() == nil &&
                fixture.viewModel.state.retryableFailedMessageIDs.contains(userMessage.id)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first { $0.content == "Queued follow-up" })
        let retryContext = try XCTUnwrap(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])
        let freshSessionCallCount = await fixture.agentsManager.freshSessionCalls().count
        XCTAssertEqual(freshSessionCallCount, 1)
        XCTAssertTrue(retryContext.contains("Restoring context from local history."))
        XCTAssertTrue(retryContext.contains("User: Summarize index.html."))
        XCTAssertTrue(retryContext.contains("Assistant: The file contains a portfolio home page."))
        XCTAssertTrue(retryContext.hasSuffix("\n\nQueued context"), retryContext)
    }
}

@MainActor
func seedLocalRestoreHistory(
    _ fixture: ConversationViewModelTestFixture,
    userMessage: String,
    assistantMessage: String? = nil
) throws {
    let conversation = try fixture.dbConversation()
    fixture.context.insert(ConversationEventRecord(
        conversationId: conversation.id,
        type: "message",
        role: "user",
        content: userMessage,
        timestamp: Date(timeIntervalSince1970: 1),
        conversation: conversation
    ))
    if let assistantMessage {
        fixture.context.insert(ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "assistant",
            content: assistantMessage,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        ))
    }
    try fixture.context.save()
}
