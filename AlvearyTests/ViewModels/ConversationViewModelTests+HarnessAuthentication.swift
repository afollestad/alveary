import Foundation
import XCTest

@testable import Alveary

/// The credential banner has to outlive the turn that failed — signing in means leaving the app, and
/// the notice is the only affordance that gets the user back to a working harness.
@MainActor
extension ConversationViewModelTests {
    func testHarnessAuthenticationNoticeSurvivesTheFailedTurn() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.markVisibleTurnStarted()
        fixture.viewModel.turnState.beginTurn()
        let message = "Failed to authenticate: OAuth session expired and could not be refreshed"

        // The mapper emits both, in this order.
        fixture.viewModel.handleEvent(.harnessAuthenticationRequired(message: message))
        fixture.viewModel.handleEvent(.error(message: message))

        XCTAssertFalse(fixture.viewModel.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.harnessAuthenticationFailure, message)
    }

    /// It persists nothing of its own: the accompanying `.error` is the transcript row, so a second
    /// record would double it.
    func testHarnessAuthenticationNoticePersistsNoRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let recordCountBefore = fixture.conversation.events.count

        fixture.viewModel.handleEvent(.harnessAuthenticationRequired(message: "OAuth session expired"))

        XCTAssertEqual(fixture.conversation.events.count, recordCountBefore)
        XCTAssertEqual(fixture.viewModel.harnessAuthenticationFailure, "OAuth session expired")
    }

    /// Outliving the failed turn is the requirement; outliving a turn the user just started is not, or
    /// signing in and sending again would leave a stale Sign In banner up for good.
    func testHarnessAuthenticationNoticeClearsWhenANewVisibleTurnStarts() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.handleEvent(.harnessAuthenticationRequired(message: "OAuth session expired"))

        fixture.viewModel.markVisibleTurnStarted()

        XCTAssertNil(fixture.viewModel.harnessAuthenticationFailure)
    }
}
