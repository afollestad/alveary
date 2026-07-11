import SwiftData
import XCTest

@testable import Alveary

// swiftlint:disable file_length

@MainActor
extension ConversationViewModelTests {
    func testViewLifecycleSubscribesOnceUntilDeactivatedAndThenResubscribes() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.activateViewLifecycle()
        XCTAssertTrue(fixture.viewModel.state.isViewMounted)
        XCTAssertEqual(fixture.viewModel.state.mountedViewCount, 1)

        try await waitUntil("view lifecycle starts a single subscription", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscribeCalls = await fixture.agentsManager.subscribeCalls()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscribeCalls == 1 && hasActiveSubscription
        }

        fixture.viewModel.deactivateViewLifecycle()
        XCTAssertFalse(fixture.viewModel.state.isViewMounted)
        XCTAssertEqual(fixture.viewModel.state.mountedViewCount, 0)

        try await waitUntil("view lifecycle cancels the active subscription", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscriptionTerminations = await fixture.agentsManager.subscriptionTerminations()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscriptionTerminations == 1 && !hasActiveSubscription
        }

        fixture.viewModel.activateViewLifecycle()
        XCTAssertTrue(fixture.viewModel.state.isViewMounted)
        XCTAssertEqual(fixture.viewModel.state.mountedViewCount, 1)

        try await waitUntil("view lifecycle resubscribes after reactivation", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let subscribeCalls = await fixture.agentsManager.subscribeCalls()
            let hasActiveSubscription = await fixture.agentsManager.hasActiveSubscription()
            return subscribeCalls == 2 && hasActiveSubscription
        }

        fixture.viewModel.deactivateViewLifecycle()
        XCTAssertFalse(fixture.viewModel.state.isViewMounted)
        XCTAssertEqual(fixture.viewModel.state.mountedViewCount, 0)

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
        XCTAssertNil(state.completedThoughtText)

        state.appendStreamingChunk("lo")

        XCTAssertEqual(state.streamingText, "Hello")
        XCTAssertNil(state.completedThoughtText)
    }

    func testStreamingChunkCompletesLiveThoughtInConversationState() {
        let state = ConversationState()

        state.appendThoughtChunk("Plan")
        state.appendStreamingChunk("Hel")

        XCTAssertNil(state.thoughtText)
        XCTAssertEqual(state.completedThoughtText, "Plan")
        XCTAssertEqual(state.completedThoughtSequence, 1)
        XCTAssertEqual(state.streamingText, "Hel")
    }

    func testThoughtChunksAppendImmediatelyInConversationState() {
        let state = ConversationState()

        state.appendThoughtChunk("Think")
        XCTAssertEqual(state.thoughtText, "Think")
        XCTAssertEqual(state.thoughtSequence, 1)

        state.appendThoughtChunk("ing")

        XCTAssertEqual(state.thoughtText, "Thinking")
        XCTAssertEqual(state.thoughtSequence, 1)
    }

    func testNewThoughtClearsCompletedThoughtInConversationState() {
        let state = ConversationState()

        state.appendThoughtChunk("Plan")
        state.appendStreamingChunk("Hel")
        state.clearAssistantStreamingText()
        state.appendThoughtChunk("Next")

        XCTAssertEqual(state.thoughtText, "Next")
        XCTAssertEqual(state.thoughtSequence, 2)
        XCTAssertNil(state.completedThoughtText)
    }

    func testThinkingEventsAccumulateWithoutPersistence() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.thinking(content: " next", parentToolUseId: nil))

        XCTAssertEqual(fixture.viewModel.thoughtText, "Plan next")
        XCTAssertEqual(fixture.viewModel.thoughtSequence, 1)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testThinkingClearsOnVisibleAssistantMessageAndLaterThoughtGetsNewSequence() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        XCTAssertEqual(fixture.viewModel.thoughtSequence, 1)

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Done", parentToolUseId: nil))
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)

        fixture.viewModel.handleEvent(.thinking(content: "Next", parentToolUseId: nil))

        XCTAssertEqual(fixture.viewModel.thoughtText, "Next")
        XCTAssertEqual(fixture.viewModel.thoughtSequence, 2)
    }

    func testThinkingClearsOnPersistedRuntimeUserMessage() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeUserMessage(content: "Follow up"))

        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)
    }

    func testThinkingDoesNotClearOnInvisibleStatusEvents() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.permissionModeChanged("acceptEdits"))
        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(sessionId: "session", name: nil, preview: nil))

        XCTAssertEqual(fixture.viewModel.thoughtText, "Plan")
        XCTAssertEqual(fixture.viewModel.thoughtSequence, 1)
    }

    func testThinkingSurvivesInterimTokenAndClearsOnTerminalToken() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: ConversationEvent.interimUsageStopReason,
            durationMs: 1,
            costUsd: nil,
            contextWindowSize: nil,
            permissionDenials: [],
            isTerminal: false
        ))

        XCTAssertEqual(fixture.viewModel.thoughtText, "Plan")

        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 1,
            costUsd: nil,
            contextWindowSize: nil,
            permissionDenials: [],
            isTerminal: true
        ))

        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)
    }

    func testParentToolThinkingDoesNotRenderAsRootThought() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Nested", parentToolUseId: "agent-1"))

        XCTAssertNil(fixture.viewModel.thoughtText)
    }

    func testStreamingMessageCompletesThoughtText() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Plan", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "Hel", parentToolUseId: nil))

        XCTAssertEqual(fixture.viewModel.streamingText, "Hel")
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertEqual(fixture.viewModel.completedThoughtText, "Plan")
        XCTAssertEqual(fixture.viewModel.completedThoughtSequence, 1)
    }

    func testStreamingChunkReplacesTransientAssistantSnapshot() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.transientAssistantMessage(content: "Commentary", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "Final", parentToolUseId: nil))

        XCTAssertEqual(fixture.viewModel.streamingText, "Final")
    }

    func testSubscriptionFlushesBufferedRootChunksAfterDelay() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Hel", parentToolUseId: nil))
        try await waitUntil("first chunk publishes immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Hel"
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "lo", parentToolUseId: nil))

        try await waitUntil("buffered root chunk flushes after max delay", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Hello"
        }

        await fixture.agentsManager.finishSubscription()
    }

    func testSubscriptionFlushesBufferedThoughtChunksAfterDelay() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.thinking(content: "Think", parentToolUseId: nil))
        try await waitUntil("first thought publishes immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.thoughtText == "Think"
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.thinking(content: "ing", parentToolUseId: nil))

        try await waitUntil("buffered thought flushes after max delay", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.thoughtText == "Thinking"
        }

        await fixture.agentsManager.finishSubscription()
    }

    func testSubscriptionResetsThoughtSequenceAfterVisibleBoundary() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.thinking(content: "Plan", parentToolUseId: nil))
        try await waitUntil("first thought publishes", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.thoughtText == "Plan"
        }
        await fixture.agentsManager.yieldSubscriptionEvent(.toolCall(
            id: "tool-1",
            name: "Bash",
            input: "{}",
            parentToolUseId: nil,
            callerAgent: nil
        ))
        try await waitUntil("tool row clears thought", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.thoughtText == nil
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.thinking(content: "Next", parentToolUseId: nil))
        try await waitUntil("later thought has new sequence", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.thoughtText == "Next" &&
                fixture.viewModel.thoughtSequence == 2
        }

        await fixture.agentsManager.finishSubscription()
    }

    func testSubscriptionContinuesRootChunksInOrderAfterDelayedFlush() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "A", parentToolUseId: nil))
        try await waitUntil("first chunk publishes immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "A"
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "B", parentToolUseId: nil))
        try await waitUntil("buffered chunk flushes after max delay", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "AB"
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "C", parentToolUseId: nil))
        try await waitUntil("next chunk continues after delayed flush", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "ABC"
        }

        await fixture.agentsManager.finishSubscription()
    }

    func testSubscriptionFlushesBufferedRootChunksBeforeNonRootEvent() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Partial", parentToolUseId: nil))
        try await waitUntil("first chunk publishes immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Partial"
        }
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: " buffered", parentToolUseId: nil))
        await fixture.agentsManager.yieldSubscriptionEvent(.runtimeActivity(state: .active, turnId: "turn-1", outcome: .unknown))

        try await waitUntil("non-root event flushes pending root chunks first", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Partial buffered" &&
                fixture.viewModel.state.lastObservedEventIndex == 3
        }

        await fixture.agentsManager.finishSubscription()
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

    func testSubscriptionContextCompactionClearsRootStreamingTextAndPersistsNote() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Partial", parentToolUseId: nil))
        try await waitUntil("streaming text appears", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Partial"
        }
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: " buffered", parentToolUseId: nil))

        await fixture.agentsManager.yieldSubscriptionEvent(.contextCompactionStarted(id: "compact-1", trigger: "auto"))

        try await waitUntil("compaction event is persisted", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
                $0.conversationId == fixture.conversation.id
            }
            return records.contains {
                $0.type == ConversationContextCompaction.startedType &&
                    $0.toolId == "compact-1"
            }
        }

        XCTAssertNil(fixture.viewModel.streamingText)
        XCTAssertEqual(fixture.viewModel.state.grouper.items, [
            .transcriptNote(id: "context-compaction-compact-1", kind: .contextCompactionStarted)
        ])

        await fixture.agentsManager.finishSubscription()
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
            into: conversation
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
                permissionDenials: [],
                isTerminal: true
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
            into: conversation
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
                permissionDenials: [],
                isTerminal: true
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
            into: conversation
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
                permissionDenials: [],
                isTerminal: true
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
        guard case .transcriptNote(_, .interrupted) = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected an interrupted transcript note")
        }
        XCTAssertEqual(fixture.viewModel.state.grouper.items.count, 1)

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["stop"])
        XCTAssertEqual(persistedEvents.first?.content, ConversationInterruption.displayMessage)
    }

    func testInterruptedMarkerTerminalizesCurrentTaskListWithoutSyntheticRecord() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(.taskListSnapshot(ConversationTaskListSnapshot(
            id: "tasks-codex-plan-turn-1",
            items: [
                ConversationTaskListItem(id: "task-1", content: "Inspect", status: .completed),
                ConversationTaskListItem(id: "task-2", content: "Patch", activeForm: "Patching", status: .inProgress),
                ConversationTaskListItem(id: "task-3", content: "Verify", status: .pending)
            ]
        )))
        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))

        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertEqual(fixture.viewModel.state.grouper.items.count, 2)
        guard case .taskListBlock("tasks-codex-plan-turn-1", let tasks) = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected interrupted task list before the interrupted note")
        }
        XCTAssertEqual(tasks.map(\.status), [.completed, .interrupted, .interrupted])
        guard case .transcriptNote(_, .interrupted) = fixture.viewModel.state.grouper.items.last else {
            return XCTFail("Expected interrupted note after the task list")
        }

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
            .filter { $0.conversationId == fixture.conversation.id }
        let taskListRecords = persistedEvents.filter { $0.type == ConversationEventRecord.taskListType }
        let stopRecords = persistedEvents.filter { $0.type == "stop" }
        XCTAssertEqual(taskListRecords.count, 1)
        XCTAssertEqual(stopRecords.count, 1)

        let restoredGrouper = ChatItemGrouper()
        restoredGrouper.update(events: [
            try XCTUnwrap(taskListRecords.first),
            try XCTUnwrap(stopRecords.first)
        ])
        guard case .taskListBlock("tasks-codex-plan-turn-1", let restoredTasks) = restoredGrouper.items.first else {
            return XCTFail("Expected restored task list before the interrupted note")
        }
        XCTAssertEqual(restoredTasks.map(\.status), [.completed, .interrupted, .interrupted])
    }

    func testLateTaskListSnapshotIsSuppressedAfterInterruptedTurn() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(.stop(message: ConversationInterruption.displayMessage))
        fixture.viewModel.handleEvent(.taskListSnapshot(ConversationTaskListSnapshot(
            id: "tasks-codex-plan-turn-1",
            items: [ConversationTaskListItem(id: "task-1", content: "Inspect", status: .inProgress)]
        )))

        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertEqual(fixture.viewModel.state.grouper.items.count, 1)
        guard case .transcriptNote(_, .interrupted) = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected only the interrupted transcript note")
        }

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.map(\.type), ["stop"])
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
