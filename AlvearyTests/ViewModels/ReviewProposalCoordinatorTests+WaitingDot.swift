import Foundation
import XCTest

@testable import Alveary

/// Covers the pending state consumed by `ConversationDecisionAttention`. Resolution and failure
/// assertions live in the base tests; `ReviewProposalCoordinatorTests+WorkingRing.swift` covers
/// the submitting span that temporarily takes precedence over the waiting dot.
@MainActor
extension ReviewProposalCoordinatorTests {
    func testAPendingProposalMarksItsSourceConversationWaiting() throws {
        let fixture = try ReviewProposalFixture()

        XCTAssertEqual(fixture.coordinator.pendingSourceConversationIDs, [fixture.conversation.id])
    }
}
