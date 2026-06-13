import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testHiddenSessionHandoffRuntimeActivityCompletesFromCollectedOutput() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.runtimeActivity(state: .active, turnId: "handoff-turn", outcome: .unknown))
        XCTAssertEqual(fixture.viewModel.state.activeRuntimeActivityTurnId, "handoff-turn")
        fixture.viewModel.handleEvent(.messageChunk(text: "Carry this context forward.", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(state: .idle, turnId: "handoff-turn", outcome: .completed))

        try await waitUntil("session handoff finished from runtime activity") {
            let freshSessionCount = await fixture.agentsManager.freshSessionCalls().count
            return !fixture.viewModel.state.isHandingOffSession && freshSessionCount == 1
        }

        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Carry this context forward.")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Carry this context forward.")
        XCTAssertNil(fixture.viewModel.state.failedSessionHandoffMessage)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(records.first { $0.role == "assistant" })
    }

    func testHiddenSessionHandoffRuntimeActivityFailureSurfacesRetry() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.runtimeActivity(
            state: .idle,
            turnId: nil,
            outcome: .failed(message: "Codex turn failed.")
        ))

        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Codex turn failed.")
        XCTAssertEqual(fixture.viewModel.state.failedSessionHandoffMessage, "Codex turn failed.")
        XCTAssertTrue(fixture.viewModel.canRetryFailedSessionHandoff)
        let freshSessionCalls = await fixture.agentsManager.freshSessionCalls()
        XCTAssertTrue(freshSessionCalls.isEmpty)
    }

    func testHiddenSessionHandoffGenericTokenFailureUsesFallbackCopy() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: true,
            stopReason: "stop_sequence",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: [],
            isTerminal: true
        ))

        XCTAssertFalse(fixture.viewModel.state.isHandingOffSession)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Session handoff failed.")
        XCTAssertEqual(fixture.viewModel.state.failedSessionHandoffMessage, "Session handoff failed.")
        XCTAssertTrue(fixture.viewModel.canRetryFailedSessionHandoff)
    }

    func testFailedSessionHandoffSuppressesTrailingRuntimeActivityAndError() async throws {
        let fixture = try ConversationViewModelTestFixture()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        fixture.viewModel.handleEvent(.error(message: "handoff prompt failed"))

        fixture.viewModel.handleEvent(.messageChunk(text: "late hidden", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.message(role: "assistant", content: "late hidden response", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.runtimeActivity(
            state: .idle,
            turnId: nil,
            outcome: .failed(message: "late runtime failure")
        ))
        fixture.viewModel.handleEvent(.error(message: "late hidden error"))

        XCTAssertNil(fixture.viewModel.streamingText)
        XCTAssertEqual(fixture.viewModel.state.failedSessionHandoffMessage, "Session handoff failed: handoff prompt failed")
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Session handoff failed: handoff prompt failed")
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertNil(records.first { $0.role == "assistant" })
    }
}
