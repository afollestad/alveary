import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ThreadDetailConversationDeletionTests: XCTestCase {
    func testSaveFailureRollsBackDeletionWithoutInvalidatingController() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversationID = fixture.conversation.persistentModelID
        let threadID = fixture.thread.persistentModelID
        fixture.thread.name = "Preserved pending edit"
        var invalidated = false

        do {
            try ThreadDetailConversationDeletion.commit(
                fixture.conversation,
                in: fixture.context,
                save: { _ in throw ThreadDetailDeletionTestError.saveFailed },
                invalidateController: { invalidated = true }
            )
            XCTFail("Expected deletion save to fail")
        } catch ThreadDetailDeletionTestError.saveFailed {
            // expected
        }

        XCTAssertFalse(invalidated)
        XCTAssertNotNil(fixture.context.resolveConversation(id: conversationID))
        let verificationContext = ModelContext(fixture.container)
        XCTAssertEqual(
            verificationContext.resolveThread(id: threadID)?.name,
            "Preserved pending edit"
        )
    }
}

private enum ThreadDetailDeletionTestError: Error {
    case saveFailed
}
