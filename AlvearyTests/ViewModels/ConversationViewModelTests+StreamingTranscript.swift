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
        XCTAssertEqual(persistedEvents.first?.content, "Interrupted")
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
