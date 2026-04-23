import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testViewLifecycleSubscribesOnceUntilDeactivatedAndThenResubscribes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.activateViewLifecycle()

        try await waitUntil("view lifecycle starts a single subscription", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscribeCalls = await fixture.agentsManager.subscribeCalls()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscribeCalls == 1 && hasActiveSubscription
        }

        fixture.viewModel.deactivateViewLifecycle()

        try await waitUntil("view lifecycle cancels the active subscription", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscriptionTerminations = await fixture.agentsManager.subscriptionTerminations()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscriptionTerminations == 1 && !hasActiveSubscription
        }

        fixture.viewModel.activateViewLifecycle()

        try await waitUntil("view lifecycle resubscribes after reactivation", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscribeCalls = await fixture.agentsManager.subscribeCalls()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscribeCalls == 2 && hasActiveSubscription
        }

        fixture.viewModel.deactivateViewLifecycle()

        try await waitUntil("second deactivation cancels the resubscribed stream", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscriptionTerminations = await fixture.agentsManager.subscriptionTerminations()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscriptionTerminations == 2 && !hasActiveSubscription
        }
    }

    func testHandleEventAppendsPersistedAssistantMessageImmediately() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Done", parentToolUseId: nil))

        let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id && $0.role == "assistant"
        }
        let assistantMessageID = try XCTUnwrap(assistantMessages.first?.id)

        XCTAssertEqual(fixture.viewModel.state.grouper.items, [.assistantMessage(id: assistantMessageID, text: "Done")])
        XCTAssertEqual(assistantMessages.map(\.content), ["Done"])
    }

    func testStreamingChunksAppendImmediatelyInConversationState() {
        let state = ConversationState()

        state.appendStreamingChunk("Hel")
        XCTAssertEqual(state.streamingText, "Hel")

        state.appendStreamingChunk("lo")

        XCTAssertEqual(state.streamingText, "Hello")
    }

    func testSubscriptionEndsTurnAfterStreamingResponseFinishes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Hel", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "lo", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.message(role: "assistant", content: "Hello", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )
        await fixture.agentsManager.finishSubscription()

        try await waitUntil("assistant response is persisted", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
                $0.conversationId == fixture.conversation.id && $0.role == "assistant"
            }
            return assistantMessages.map(\.content) == ["Hello"]
        }

        try await waitUntil("turn ends after streamed response", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            !fixture.viewModel.turnState.isActive
        }

        let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id && $0.role == "assistant"
        }
        let sessionInitEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id && $0.type == "session_init"
        }

        XCTAssertEqual(assistantMessages.map(\.content), ["Hello"])
        XCTAssertTrue(sessionInitEvents.isEmpty)
        XCTAssertNil(fixture.viewModel.streamingText)
    }

    func testSubscriptionPersistsAssistantFailureMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(
            .message(
                role: "assistant",
                content: "Unknown command: /test-command",
                parentToolUseId: nil
            )
        )
        await fixture.agentsManager.yieldSubscriptionEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "Unknown command: /test-command",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )
        await fixture.agentsManager.finishSubscription()

        try await waitUntil("assistant failure message is persisted", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
                $0.conversationId == fixture.conversation.id && $0.role == "assistant"
            }
            return assistantMessages.map(\.content) == ["Unknown command: /test-command"]
        }

        let assistantMessages = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id && $0.role == "assistant"
        }
        XCTAssertEqual(assistantMessages.map(\.content), ["Unknown command: /test-command"])
    }

    func testZeroTokenSlashCommandTurnSynthesizesAssistantNotice() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage(
            "/test-command",
            into: conversation,
            shouldAutoNameThread: false
        )

        fixture.viewModel.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: nil,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        let assistantMessages = persistedEvents.filter { $0.role == "assistant" }
        let tokenEvents = persistedEvents.filter { $0.type == "tokens" }

        XCTAssertEqual(assistantMessages.map(\.content), ["Unknown command: /test-command"])
        XCTAssertTrue(tokenEvents.isEmpty)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testZeroTokenSlashCommandTurnDoesNotSynthesizeNoticeAfterToolActivity() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage(
            "/test-command",
            into: conversation,
            shouldAutoNameThread: false
        )
        fixture.viewModel.handleEvent(
            .toolCall(
                id: "tool-1",
                name: "Read",
                input: "{\"filePath\":\"README.md\"}",
                parentToolUseId: nil,
                callerAgent: nil
            )
        )
        fixture.viewModel.handleEvent(
            .toolResult(
                id: "tool-1",
                output: "stdout",
                isError: false,
                parentToolUseId: nil,
                metadata: nil
            )
        )

        fixture.viewModel.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: nil,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        let assistantMessages = persistedEvents.filter { $0.role == "assistant" }
        let tokenEvents = persistedEvents.filter { $0.type == "tokens" }

        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(tokenEvents.count, 1)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testZeroTokenSlashCommandTurnDoesNotSynthesizeNoticeAfterStreamingChunkActivity() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage(
            "/test-command",
            into: conversation,
            shouldAutoNameThread: false
        )
        fixture.viewModel.handleEvent(
            .messageChunk(
                text: "Working on it...",
                parentToolUseId: nil
            )
        )

        fixture.viewModel.handleEvent(
            .tokens(
                input: 0,
                output: 0,
                cacheRead: 0,
                isError: false,
                stopReason: nil,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        )

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        let assistantMessages = persistedEvents.filter { $0.role == "assistant" }
        let tokenEvents = persistedEvents.filter { $0.type == "tokens" }

        XCTAssertTrue(assistantMessages.isEmpty)
        XCTAssertEqual(tokenEvents.count, 1)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }

    func testCancellationMarksTurnInterruptedInsteadOfSettingError() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isCancellingTurn = true

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: nil,
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertNil(fixture.viewModel.lastTurnError)

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["stop"])
        XCTAssertEqual(persistedEvents.first?.content, ConversationInterruption.displayMessage)
    }

    func testCancellationDuringToolUseMarksTurnInterrupted() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isCancellingTurn = true

        // Claude CLI reports `is_error: true` with `stop_reason: "tool_use"` when a turn is
        // cancelled mid tool call. That is an interruption, not a genuine failure.
        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "tool_use",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertNil(fixture.viewModel.lastTurnError)

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["stop"])
        XCTAssertEqual(persistedEvents.first?.content, ConversationInterruption.displayMessage)
    }

    func testPermissionDeniedToolUseEndsTurnWithoutSettingError() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "tool_use",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: [PermissionDenialSummary(toolName: "Bash", toolUseId: "tool-1")]
            )
        )

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertNil(fixture.viewModel.lastTurnError)

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["tokens"])
        XCTAssertEqual(persistedEvents.first?.stopReason, "tool_use")
    }

    func testExplicitInterruptedMarkerPersistsStopAndSuppressesTrailingErrorTokens() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))
        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 0,
                cacheRead: 0,
                isError: true,
                stopReason: ConversationInterruption.requestInterruptedByUserReason,
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        guard case .turnInterruptedNote = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected an interrupted transcript note")
        }
        XCTAssertEqual(fixture.viewModel.state.grouper.items.count, 1)

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["stop"])
        XCTAssertEqual(persistedEvents.first?.content, ConversationInterruption.displayMessage)
    }

    func testCancellationDoesNotMaskRealTurnFailures() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isCancellingTurn = true

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "Agent process crashed unexpectedly",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Agent process crashed unexpectedly")

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["tokens"])
        XCTAssertEqual(persistedEvents.first?.stopReason, "Agent process crashed unexpectedly")
    }
}
