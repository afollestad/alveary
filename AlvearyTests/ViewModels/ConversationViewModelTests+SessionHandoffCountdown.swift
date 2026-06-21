import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSessionHandoffCountdownTaskAutoSendDoesNotCancelItsOwnSend() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.settingsService.update {
            $0.handoffPromptSendCountdownSeconds = 1
        }
        await fixture.agentsManager.failSendWhenCurrentTaskIsCancelled()

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Auto-send after countdown.", parentToolUseId: nil))
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

        try await waitUntil(
            "handoff output auto-sent from countdown task",
            timeout: .seconds(3),
            pollInterval: .milliseconds(25)
        ) {
            await fixture.agentsManager.sentMessages() == [
                AppSettings.defaultSessionHandoffPrompt,
                "Auto-send after countdown."
            ]
        }

        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertNil(fixture.viewModel.state.pendingHandoffOutput)
        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Auto-send after countdown."])
    }
}
