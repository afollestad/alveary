import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSteerFailureKeepsRetryableTranscriptAttempt() async throws {
        let fixture = try ConversationViewModelTestFixture(sendError: .sendFailed)
        await fixture.agentsManager.setStatus(.busy, for: fixture.conversation.id)

        do {
            try await fixture.viewModel.steer("Steer now")
            XCTFail("Expected steer to fail")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "Steer now")
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertNil(fixture.viewModel.state.retryableFailedMessageStagedContexts[failedMessage.id])
        XCTAssertTrue(fixture.viewModel.lastTurnError?.hasPrefix("Steer failed:") == true)
        XCTAssertFalse(fixture.viewModel.turnState.isActive)
    }
}
