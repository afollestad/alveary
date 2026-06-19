import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSteerNextQueuedMessageSendsOnlyHeadQueuedMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "First context"
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("First queued")
        fixture.viewModel.state.stagedContext = "Second context"
        try await fixture.viewModel.queueOrSend("Second queued")

        try await fixture.viewModel.steerNextQueuedMessage()

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["First context\n\nFirst queued"])
        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Second queued"])
        let userMessages = try fixture.userMessages()
        XCTAssertEqual(userMessages.map(\.content), ["First queued"])
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        XCTAssertEqual(steeringCalls, [
            .init(
                message: "First context\n\nFirst queued",
                conversationId: fixture.conversation.id,
                steeringInputID: try XCTUnwrap(userMessages.first?.id)
            )
        ])
        XCTAssertNil(fixture.viewModel.state.inFlightQueuedMessageID)
    }

    func testSteerNextQueuedMessageNoOpsWhenQueueIsEmpty() async throws {
        let fixture = try ConversationViewModelTestFixture()

        try await fixture.viewModel.steerNextQueuedMessage()

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testSteerNextQueuedMessageDoesNotSkipPlanModeHeadMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Plan queued", requiredPlanModeEnabled: true)
        try await fixture.viewModel.queueOrSend("Normal queued")

        do {
            try await fixture.viewModel.steerNextQueuedMessage()
            XCTFail("Expected plan-mode queued message steering to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Plan-mode queued messages send on the next turn")
        }

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Plan queued", "Normal queued"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }

    func testSteerNextQueuedMessageDoesNotSkipSpeedModeHeadMessage() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.turnState.beginTurn()
        try await fixture.viewModel.queueOrSend("Fast queued", requiredSpeedMode: .fast)
        try await fixture.viewModel.queueOrSend("Normal queued")

        do {
            try await fixture.viewModel.steerNextQueuedMessage()
            XCTFail("Expected speed-mode queued message steering to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Speed-mode queued messages send on the next turn")
        }

        XCTAssertEqual(fixture.viewModel.messageQueue.pending.map(\.text), ["Fast queued", "Normal queued"])
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertTrue(sentMessages.isEmpty)
    }
}
