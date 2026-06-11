import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSendDuringTurnCancellationDoesNotInsertRetryableAttempt() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.isCancellingTurn = true

        do {
            try await fixture.viewModel.send("Continue after interrupt")
            XCTFail("Expected send to throw")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertTrue(message.contains("interruption"))
        } catch {
            XCTFail("Expected spawnFailed, got \(error)")
        }

        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
    }

    func testBlockedOutboundReadinessDoesNotInsertRetryableAttempt() async throws {
        let fixture = try ConversationViewModelTestFixture()
        await fixture.agentsManager.enqueueOutboundReadiness(.blocked(reason: "Waiting for approval."))

        do {
            try await fixture.viewModel.send("Continue after interrupt")
            XCTFail("Expected send to throw")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertEqual(message, "Waiting for approval.")
        } catch {
            XCTFail("Expected spawnFailed, got \(error)")
        }

        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
    }
}
