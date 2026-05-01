import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testHiddenSessionHandoffIgnoresInterimUsageBeforeOutput() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 0,
            cacheRead: 0,
            isError: false,
            stopReason: "usage_update",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        let freshSessionCallsBeforeOutput = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(freshSessionCallsBeforeOutput.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.isHandingOffSession)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)

        fixture.viewModel.handleEvent(.messageChunk(text: "Recovered ", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "context.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        try await waitUntil("session handoff recovered") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Recovered context.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Recovered context.")
    }

    func testHiddenSessionHandoffStripsOuterMarkdownFenceBeforeCustomization() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.message(
            role: "assistant",
            content: "```markdown\nPrimary goal:\n- Continue the work.\n```",
            parentToolUseId: nil
        ))
        fixture.viewModel.handleEvent(.tokens(
            input: 10,
            output: 5,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0.01,
            contextWindowSize: 200,
            permissionDenials: []
        ))

        try await waitUntil("session handoff finished hidden response") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Primary goal:\n- Continue the work.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Primary goal:\n- Continue the work.")
    }
}
