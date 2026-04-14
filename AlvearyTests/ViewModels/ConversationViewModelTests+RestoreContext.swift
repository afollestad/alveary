import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSendPrependsStagedContextOnlyToTransport() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.stagedContext = "Context block"

        try await fixture.viewModel.send("Fix the auth bug")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Context block\n\nFix the auth bug"])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Fix the auth bug"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertTrue(fixture.viewModel.turnState.isActive)
    }

    func testPendingRestoreContextHydratesIntoComposerAndClearsAfterSend() async throws {
        let fixture = try ConversationViewModelTestFixture(pendingRestoreContext: "Restored summary")

        fixture.viewModel.activateViewLifecycle()

        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Restored summary")

        try await fixture.viewModel.send("Continue from there")

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Restored summary\n\nContinue from there"])
        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertNil(try fixture.dbConversation().pendingRestoreContext)
    }

    func testDismissStagedContextClearsPendingRestoreContext() throws {
        let fixture = try ConversationViewModelTestFixture(pendingRestoreContext: "Restored summary")

        fixture.viewModel.activateViewLifecycle()

        fixture.viewModel.dismissStagedContext()

        XCTAssertNil(fixture.viewModel.state.stagedContext)
        XCTAssertNil(try fixture.dbConversation().pendingRestoreContext)
    }
}
