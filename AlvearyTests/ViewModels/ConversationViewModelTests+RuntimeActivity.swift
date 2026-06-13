import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testRuntimeActivityCompletedIdleEndsTurnWithoutPersistingRecord() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
        XCTAssertNil(fixture.viewModel.streamingText)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    func testRuntimeActivityNilIdleCompletesStoredTurn() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
    }

    func testRuntimeActivityStaleExplicitIdleIsIgnored() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-current"
        fixture.viewModel.state.appendStreamingChunk("Partial")

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: "turn-old", outcome: .completed))

        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.state.activeRuntimeActivityTurnId, "turn-current")
        XCTAssertEqual(fixture.viewModel.streamingText, "Partial")
    }

    func testRuntimeActivityFailedIdleEndsTurnWithoutDrainingQueuedMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleEvent(.runtimeActivity(
            state: .idle,
            turnId: nil,
            outcome: .failed(message: "Codex turn failed.")
        ))

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.messageQueue.peekNext()?.text, "Follow-up")
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Codex turn failed.")
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testRuntimeActivityCompletedIdleDrainsQueuedMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.state.turnState.beginTurn()

        try await fixture.viewModel.queueOrSend("Follow-up")
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        try await waitUntil("queued message sent after runtime idle") {
            await fixture.agentsManager.sentMessages() == ["Follow-up"] &&
                fixture.viewModel.messageQueue.peekNext() == nil
        }

        XCTAssertTrue(fixture.viewModel.turnState.isActive)
        XCTAssertNil(fixture.viewModel.lastTurnError)
    }

    func testRuntimeActivityInterruptedIdlePersistsOneStopAndSuppressesCancellationError() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        fixture.viewModel.handleEvent(.error(message: "No active turn to cancel"))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertNil(fixture.viewModel.lastTurnError)

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let stopRecords = records.filter { $0.type == "stop" }
        let errorRecords = records.filter { $0.type == "error" }
        XCTAssertEqual(stopRecords.count, 1)
        XCTAssertTrue(errorRecords.isEmpty)
        XCTAssertEqual(stopRecords.first?.content, ConversationInterruption.displayMessage)
    }

    func testRuntimeActivityInterruptedIdleTerminalizesRunningCommandTool() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.grouper.append(event: ConversationEventRecord(
            id: "cmd-1",
            conversationId: fixture.conversation.id,
            type: "tool_call",
            toolId: "cmd-1",
            toolName: "CommandExecution",
            toolInput: #"{"command":"swift test"}"#
        ))

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))

        guard case .standaloneTool(_, let tool) = fixture.viewModel.state.grouper.items.first else {
            return XCTFail("Expected the running command to stay visible as a standalone row")
        }
        XCTAssertTrue(tool.isComplete)
        XCTAssertTrue(tool.isInterrupted)
        XCTAssertFalse(tool.transcriptDisplaySummary.hasPrefix("Running "))
    }

    func testRealErrorAfterInterruptedTurnPersists() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .interrupted))
        fixture.viewModel.handleEvent(.error(message: "Agent process crashed unexpectedly"))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertFalse(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.visibleTranscriptItems.contains { item in
            if case .error(_, "Agent process crashed unexpectedly") = item {
                return true
            }
            return false
        })

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let stopRecords = records.filter { $0.type == "stop" }
        let errorRecords = records.filter { $0.type == "error" }
        XCTAssertEqual(stopRecords.count, 1)
        XCTAssertEqual(errorRecords.map(\.content), ["Agent process crashed unexpectedly"])
    }

    func testProviderErrorDeduplicatesAssistantFailureAndSuppressesGenericComposerError() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let failureMessage = """
        There's an issue with the selected model (claude-fable-5). It may not exist or you may not have access to it.
        """

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage("Use claude-fable-5", into: conversation)
        fixture.viewModel.handleEvent(.message(role: "assistant", content: failureMessage, parentToolUseId: nil))
        fixture.viewModel.handleEvent(.error(message: failureMessage))
        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: true,
            stopReason: "stop_sequence",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))

        let persistedEvents = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertEqual(persistedEvents.filter { $0.role == "assistant" }.map(\.content), [failureMessage])
        XCTAssertEqual(persistedEvents.filter { $0.type == "error" }.map(\.content), [failureMessage])
        XCTAssertEqual(persistedEvents.filter { $0.type == "tokens" }.map(\.stopReason), ["stop_sequence"])
        XCTAssertNil(fixture.viewModel.lastTurnError)

        let visibleItems = fixture.viewModel.state.grouper.items.visibleTranscriptItems
        let userRecord = try XCTUnwrap(persistedEvents.first { $0.role == "user" })
        XCTAssertTrue(visibleItems.contains(.userMessage(id: userRecord.id, text: "Use claude-fable-5")))
        XCTAssertFalse(visibleItems.contains { item in
            if case .assistantMessage = item {
                return true
            }
            return false
        })
        XCTAssertEqual(
            visibleItems.compactMap { item -> String? in
                guard case .error(_, let message) = item else {
                    return nil
                }
                return message
            },
            [failureMessage]
        )
    }

    func testAssistantOnlyFailureSuppressesGenericTokenComposerError() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()

        fixture.viewModel.state.turnState.beginTurn()
        _ = fixture.viewModel.insertLocalUserMessage("Use claude-fable-5", into: conversation)
        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Selected model is unavailable.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: true,
            stopReason: "stop_sequence",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))

        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.visibleTranscriptItems.contains { item in
            if case .assistantMessage(_, "Selected model is unavailable.") = item {
                return true
            }
            return false
        })
    }

    func testTokenOnlyGenericFailureUsesComposerFallbackCopy() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: true,
            stopReason: "stop_sequence",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))

        XCTAssertEqual(fixture.viewModel.lastTurnError, "Agent turn failed")
    }

    func testRuntimeActivityCompletedIdleDuringCancellationSynthesizesInterruption() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.isCancellingTurn = true
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertFalse(fixture.viewModel.state.isCancellingTurn)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertEqual(records.map(\.type), ["stop"])
    }

    func testRuntimeActivityResetsRootChunkBoundary() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "First", parentToolUseId: nil))
        try await waitUntil("first chunk published immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "First"
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.runtimeActivity(state: .idle, turnId: nil, outcome: .completed))
        try await waitUntil("runtime idle clears streaming text", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == nil
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Next", parentToolUseId: nil))
        try await waitUntil("next turn first chunk publishes immediately", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.streamingText == "Next"
        }

        await fixture.agentsManager.finishSubscription()
    }

    func testRuntimeActivityCursorIsAcknowledgedAfterSave() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.runtimeActivity(
            state: .active,
            turnId: "turn-1",
            outcome: .unknown
        ))

        try await waitUntil("runtime activity observed", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.state.lastObservedEventIndex == 1
        }
        await fixture.viewModel.flushPendingSaveIfNeeded()

        let calls = await fixture.agentsManager.markPersistedCalls()
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 1)
        XCTAssertEqual(calls.last?.conversationId, fixture.conversation.id)
        XCTAssertEqual(calls.last?.index, 1)
    }
}
