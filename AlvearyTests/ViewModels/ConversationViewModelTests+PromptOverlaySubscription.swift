import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testDismissPromptSuppressesBufferedSubscriptionChunksBeforeResolutionReturns() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let seededPrompt = try seedSubscriptionPromptApproval(in: fixture)
        try await startPromptOverlaySubscription(in: fixture)
        await fixture.agentsManager.pauseApprovalResolution()

        let dismissTask = Task { @MainActor in
            try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")
        }
        defer { dismissTask.cancel() }
        try await waitUntil("expected dismiss to pause during provider resolution") {
            await fixture.agentsManager.isApprovalResolutionPaused()
        }

        try await yieldBufferedPromptDismissalFallbackChunks(in: fixture)

        XCTAssertNil(fixture.viewModel.state.streamingText)
        XCTAssertNil(fixture.viewModel.state.lastTurnError)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.visibleTranscriptItems.isEmpty)
        assertNoPromptDismissalFallbackRecords(in: fixture)

        await fixture.agentsManager.resumeApprovalResolution()
        try await dismissTask.value

        XCTAssertNil(fixture.viewModel.state.streamingText)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertEqual(seededPrompt.promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
        assertNoPromptDismissalFallbackRecords(in: fixture)
        await fixture.agentsManager.finishSubscription()
    }

    func testDismissPromptSuppressesLateBufferedSubscriptionChunksAfterResolutionReturns() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let seededPrompt = try seedSubscriptionPromptApproval(in: fixture)
        try await startPromptOverlaySubscription(in: fixture)

        try await fixture.viewModel.dismissPrompt(promptId: "prompt-1")
        try await yieldBufferedPromptDismissalFallbackChunks(in: fixture)

        XCTAssertNil(fixture.viewModel.state.streamingText)
        XCTAssertNil(fixture.viewModel.state.lastTurnError)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertTrue(fixture.viewModel.state.lastTurnInterrupted)
        XCTAssertTrue(fixture.viewModel.state.shouldShowInterruptedCue)
        XCTAssertEqual(seededPrompt.promptRecord.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertFalse(fixture.viewModel.hasUnansweredPrompt)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.visibleTranscriptItems.isEmpty)
        assertNoPromptDismissalFallbackRecords(in: fixture)
        await fixture.agentsManager.finishSubscription()
    }
}

@MainActor
private func seedSubscriptionPromptApproval(
    in fixture: ConversationViewModelTestFixture
) throws -> (promptRecord: ConversationEventRecord, approval: ToolApprovalRequest) {
    let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
    let conversation = try fixture.dbConversation()
    let promptRecord = ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_call",
        toolId: "prompt-1",
        toolName: "AskUserQuestion",
        toolInput: promptInput,
        timestamp: Date(timeIntervalSince1970: 1),
        conversation: conversation
    )
    let approval = ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: "prompt-1",
        toolName: "AskUserQuestion",
        toolInput: promptInput
    )
    fixture.context.insert(promptRecord)
    fixture.context.insert(ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: approval.sessionId,
        toolId: approval.toolUseId,
        toolName: approval.toolName,
        toolInput: approval.toolInput,
        timestamp: Date(timeIntervalSince1970: 2),
        conversation: conversation
    ))
    try fixture.context.save()
    fixture.viewModel.state.turnState.beginTurn()
    fixture.viewModel.state.grouper.append(event: promptRecord)
    fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
    return (promptRecord, approval)
}

@MainActor
private func startPromptOverlaySubscription(in fixture: ConversationViewModelTestFixture) async throws {
    await fixture.agentsManager.enableSubscription()
    fixture.viewModel.subscribe()
    try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        await fixture.agentsManager.hasActiveSubscription()
    }
}

@MainActor
private func yieldBufferedPromptDismissalFallbackChunks(in fixture: ConversationViewModelTestFixture) async throws {
    let startingIndex = fixture.viewModel.state.lastObservedEventIndex
    await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Permission denied. ", parentToolUseId: nil))
    for index in 0..<8 {
        await fixture.agentsManager.yieldSubscriptionEvent(.messageChunk(text: "Fallback chunk \(index). ", parentToolUseId: nil))
    }
    try await waitUntil("buffered prompt dismissal chunks flushed", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        fixture.viewModel.state.lastObservedEventIndex >= startingIndex + 9
    }
}

@MainActor
private func assertNoPromptDismissalFallbackRecords(
    in fixture: ConversationViewModelTestFixture,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        XCTAssertFalse(records.contains {
            ($0.type == "message" && $0.content?.contains("Permission denied") == true) ||
                ($0.type == "stop" && $0.content == ConversationInterruption.displayMessage) ||
                $0.toolName == "ExitPlanMode"
        }, file: file, line: line)
    } catch {
        XCTFail("Failed to fetch prompt overlay records: \(error)", file: file, line: line)
    }
}
