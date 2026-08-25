import Foundation
import XCTest

@testable import Alveary

/// The credential banner has to outlive the turn that failed — signing in means leaving the app, and
/// the notice is the only affordance that gets the user back to a working provider.
@MainActor
extension ConversationViewModelTests {
    func testProviderAuthenticationNoticeSurvivesTheFailedTurn() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let message = "Failed to authenticate: OAuth session expired and could not be refreshed"

        // The mapper emits both, in this order.
        fixture.viewModel.handleEvent(.providerAuthenticationRequired(message: message))
        fixture.viewModel.handleEvent(.error(message: message))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.providerAuthenticationFailure, message)
    }

    /// It persists nothing of its own: the accompanying `.error` is the transcript row, so a second
    /// record would double it.
    func testProviderAuthenticationNoticePersistsNoRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let recordCountBefore = fixture.conversation.events.count

        fixture.viewModel.handleEvent(.providerAuthenticationRequired(message: "OAuth session expired"))

        XCTAssertEqual(fixture.conversation.events.count, recordCountBefore)
        XCTAssertEqual(fixture.viewModel.providerAuthenticationFailure, "OAuth session expired")
    }

    /// Outliving the failed turn is the requirement; outliving a turn the user just started is not, or
    /// signing in and sending again would leave a stale Sign In banner up for good.
    func testProviderAuthenticationNoticeClearsWhenANewVisibleTurnStarts() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.handleEvent(.providerAuthenticationRequired(message: "OAuth session expired"))

        fixture.viewModel.markVisibleTurnStarted()

        XCTAssertNil(fixture.viewModel.providerAuthenticationFailure)
    }

    func testProviderAuthenticationNoticeIsDismissable() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.handleEvent(.providerAuthenticationRequired(message: "OAuth session expired"))

        fixture.viewModel.providerAuthenticationFailure = nil

        XCTAssertNil(fixture.viewModel.providerAuthenticationFailure)
    }
}
