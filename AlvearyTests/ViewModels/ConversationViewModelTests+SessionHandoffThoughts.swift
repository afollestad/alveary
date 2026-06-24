import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testHiddenSessionHandoffClearsAndSuppressesThoughtText() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.thinking(content: "Visible thought", parentToolUseId: nil))
        fixture.viewModel.handleEvent(.messageChunk(text: "Draft", parentToolUseId: nil))
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertEqual(fixture.viewModel.completedThoughtText, "Visible thought")

        await fixture.viewModel.startSessionHandoff(trigger: .manual)
        try await waitUntil("handoff prompt sent") {
            await fixture.agentsManager.sentMessages() == [AppSettings.defaultSessionHandoffPrompt]
        }
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)

        fixture.viewModel.handleEvent(.thinking(content: "Hidden thought", parentToolUseId: nil))
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)

        fixture.viewModel.handleEvent(.message(role: "assistant", content: "Carry this context forward.", parentToolUseId: nil))
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
        XCTAssertNil(fixture.viewModel.thoughtText)
        XCTAssertNil(fixture.viewModel.completedThoughtText)
    }
}
