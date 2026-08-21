import Foundation
import XCTest

@testable import Alveary

/// The working half of the pair `ConversationDecisionAttentionTests` covers. Separate suite rather
/// than a companion file, because the type is separate and shares none of that one's SwiftData seed:
/// `isWorking` takes an id, so nothing here needs a live row.
@MainActor
final class ConversationWorkActivityTests: XCTestCase {
    func testNoSourcesMeansNoWork() {
        XCTAssertFalse(ConversationWorkActivity.none.isWorking("conversation-1"))
    }

    func testAPublishingReviewFlipsIt() {
        let activity = ConversationWorkActivity(publishingReviewConversationIDs: ["conversation-1"])

        XCTAssertTrue(activity.isWorking("conversation-1"))
        XCTAssertFalse(activity.isWorking("conversation-2"))
    }

    /// Previews and snapshot hosts mount the status surfaces without the app root's environment.
    func testAnAbsentCoordinatorDegradesToNoWork() {
        let activity = ConversationWorkActivity(reviewProposals: nil)

        XCTAssertEqual(activity, .none)
    }

    /// The one live source, read the way both surfaces read it.
    func testItReadsTheCoordinatorsInFlightSubmissions() throws {
        let fixture = try ReviewProposalFixture()
        XCTAssertEqual(
            ConversationWorkActivity(reviewProposals: fixture.coordinator),
            .none
        )

        fixture.coordinator.beginSubmitting(
            ReviewProposalFixture.proposalID,
            conversationID: fixture.conversation.id
        )
        defer {
            fixture.coordinator.endSubmitting(
                ReviewProposalFixture.proposalID,
                conversationID: fixture.conversation.id
            )
        }

        XCTAssertTrue(
            ConversationWorkActivity(reviewProposals: fixture.coordinator)
                .isWorking(fixture.conversation.id)
        )
    }
}
