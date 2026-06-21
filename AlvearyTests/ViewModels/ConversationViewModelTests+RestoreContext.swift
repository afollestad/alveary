import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSendPrependsStagedContextOnlyToTransport() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Context block"

        try await fixture.viewModel.send("Fix the auth bug")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Context block\n\nFix the auth bug"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Fix the auth bug"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testPendingRestoreContextHydratesIntoComposerAndClearsAfterSend() async throws {
        let fixture = try ConversationViewModelTestFixture(pendingRestoreContext: "Restored summary")

        fixture.viewModel.activateViewLifecycle()

        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Restored summary")

        try await fixture.viewModel.send("Continue from there")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Restored summary\n\nContinue from there"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertNil(try fixture.dbConversation().pendingRestoreContext)
    }

    func testDismissStagedContextClearsPendingRestoreContext() throws {
        let fixture = try ConversationViewModelTestFixture(pendingRestoreContext: "Restored summary")

        fixture.viewModel.activateViewLifecycle()

        fixture.viewModel.dismissStagedContext()

        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertNil(try fixture.dbConversation().pendingRestoreContext)
    }

    func testSendStartsFreshSessionWithLocalContextWhenStoredCodexSessionCannotResume() async throws {
        let fixture = try ConversationViewModelTestFixture(
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        try seedLocalRestoreHistory(
            fixture,
            userMessage: "Summarize index.html.",
            assistantMessage: "The file contains a portfolio home page."
        )
        await fixture.agentsManager.enqueueSpawnError(
            CodexAppServerError.jsonRPCError(
                method: "thread/resume",
                code: -32600,
                message: "no rollout found for thread id 019ee845-0b26-7061-af79-9bd2327f8401"
            )
        )
        await fixture.agentsManager.enqueueOutboundReadiness(.respawnRequired)
        XCTAssertNotNil(fixture.viewModel.localRestoreContextForNonresumableSession())
        XCTAssertFalse(fixture.viewModel.needsSetup)

        try await fixture.viewModel.send("Continue from there")

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentMessage = try XCTUnwrap(sentMessages.first)
        let spawnCallCount = await fixture.agentsManager.spawnCalls().count
        let freshSessionCallCount = await fixture.agentsManager.freshSessionCalls().count
        XCTAssertEqual(spawnCallCount, 1, "spawnCallCount")
        XCTAssertEqual(freshSessionCallCount, 1, "freshSessionCallCount")
        XCTAssertEqual(sentMessages.count, 1)
        XCTAssertTrue(sentMessage.contains("Restoring context from local history."))
        XCTAssertTrue(sentMessage.contains("User: Summarize index.html."))
        XCTAssertTrue(sentMessage.contains("Assistant: The file contains a portfolio home page."))
        XCTAssertTrue(sentMessage.hasSuffix("\n\nContinue from there"), sentMessage)
        let visibleMessages = try fixture.userMessages().compactMap(\.content).sorted()
        XCTAssertEqual(visibleMessages, ["Continue from there", "Summarize index.html."])
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testRecoveredNonresumableSendFailureKeepsLocalContextForRetry() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        try seedLocalRestoreHistory(
            fixture,
            userMessage: "Summarize index.html.",
            assistantMessage: "The file contains a portfolio home page."
        )
        await fixture.agentsManager.enqueueSendResult(.failure(.stdinClosed))
        await fixture.agentsManager.enqueueOutboundReadiness(.ready)
        await fixture.agentsManager.enqueueOutboundReadiness(.respawnRequired)
        await fixture.agentsManager.enqueueSpawnError(
            CodexAppServerError.jsonRPCError(
                method: "thread/resume",
                code: -32600,
                message: "no rollout found for thread id 019ee845-0b26-7061-af79-9bd2327f8401"
            )
        )
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        do {
            try await fixture.viewModel.send("Continue from there")
            XCTFail("Expected recovered send to fail")
        } catch MockAgentsManager.MockError.sendFailed {}

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first { $0.content == "Continue from there" })
        let retryContext = try XCTUnwrap(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])
        let freshSessionCallCount = await fixture.agentsManager.freshSessionCalls().count
        XCTAssertEqual(freshSessionCallCount, 1)
        XCTAssertTrue(retryContext.contains("Restoring context from local history."))
        XCTAssertTrue(retryContext.contains("User: Summarize index.html."))
        XCTAssertTrue(retryContext.contains("Assistant: The file contains a portfolio home page."))
    }

    func testSendStartsFreshSessionWithLocalContextWhenCodexSendCannotResume() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        try seedLocalRestoreHistory(
            fixture,
            userMessage: "Summarize index.html.",
            assistantMessage: "The file contains a portfolio home page."
        )
        await fixture.agentsManager.enqueueSendError(
            CodexAppServerError.jsonRPCError(
                method: "thread/resume",
                code: -32600,
                message: "no rollout found for thread id 019ee845-0b26-7061-af79-9bd2327f8401"
            )
        )

        try await fixture.viewModel.send("Continue from there")

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentMessage = try XCTUnwrap(sentMessages.first)
        let freshSessionCallCount = await fixture.agentsManager.freshSessionCalls().count
        XCTAssertEqual(freshSessionCallCount, 1)
        XCTAssertEqual(sentMessages.count, 1)
        XCTAssertTrue(sentMessage.contains("Restoring context from local history."))
        XCTAssertTrue(sentMessage.contains("User: Summarize index.html."))
        XCTAssertTrue(sentMessage.contains("Assistant: The file contains a portfolio home page."))
        XCTAssertTrue(sentMessage.hasSuffix("\n\nContinue from there"), sentMessage)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testNonresumableProviderSessionDetectionRecognizesResumeMissingConversationText() throws {
        let fixture = try ConversationViewModelTestFixture()

        XCTAssertTrue(
            fixture.viewModel.isNonresumableProviderSessionError(
                AgentError.spawnFailed("Resume failed: no conversation found for session abc123")
            )
        )
        XCTAssertFalse(
            fixture.viewModel.isNonresumableProviderSessionError(
                AgentError.spawnFailed("Working directory not found")
            )
        )
    }
}
