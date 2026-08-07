import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// The stored envelope's version contract: older versions decode, newer ones refuse — a confirm
/// must never submit less than the card the user saw.
@MainActor
final class PullRequestReviewProposalRecordTests: XCTestCase {
    private var container: ModelContainer?

    func testAVersionOneEnvelopeDecodesWithNoStagedComments() throws {
        let conversation = try makeConversation()
        // Written by the build before staged comments existed: version 1, no `comments` key.
        conversation.pullRequestReviewProposalJSON = """
        {"body":"Looks good.","createdAt":"2024-01-01T00:00:00Z","deduplicationKey":"d1",\
        "event":"approve","id":"p1","number":7,"payloadVersion":1,\
        "pendingCommentCountSnapshot":1,"repositoryNameWithOwner":"octo/alpha",\
        "sourceProcessToken":"t","sourceRequestID":"r","titleSnapshot":"Title"}
        """

        let record = try XCTUnwrap(conversation.pullRequestReviewProposal())

        XCTAssertEqual(record.payloadVersion, 1)
        XCTAssertTrue(record.stagedComments.isEmpty)
        XCTAssertEqual(record.displayKey, "octo/alpha#7")
    }

    func testANewerEnvelopeVersionIsRefusedRatherThanPartiallyRead() throws {
        let conversation = try makeConversation()
        let newerVersion = PullRequestReviewProposalRecord.currentPayloadVersion + 1
        try conversation.storePullRequestReviewProposal(makeRecord(payloadVersion: newerVersion))

        XCTAssertThrowsError(try conversation.pullRequestReviewProposal()) { error in
            XCTAssertEqual(
                error as? PullRequestReviewProposalStorageError,
                .unsupportedPayloadVersion(newerVersion)
            )
        }
    }

    func testStagedCommentsRoundTripInOrder() throws {
        let conversation = try makeConversation()
        let comments = [
            PullRequestReviewProposalRecord.Comment(path: "A.swift", line: 3, side: "RIGHT", body: "First"),
            PullRequestReviewProposalRecord.Comment(path: "B.swift", line: 9, side: "LEFT", body: "Second")
        ]
        try conversation.storePullRequestReviewProposal(makeRecord(comments: comments))

        let record = try XCTUnwrap(conversation.pullRequestReviewProposal())

        XCTAssertEqual(record.stagedComments, comments)
    }
}

private extension PullRequestReviewProposalRecordTests {
    func makeConversation() throws -> Conversation {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let context = ModelContext(container)
        let thread = AgentThread(name: "Thread")
        let conversation = Conversation(id: "c1", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        context.insert(thread)
        try context.save()
        return conversation
    }

    func makeRecord(
        payloadVersion: Int = PullRequestReviewProposalRecord.currentPayloadVersion,
        comments: [PullRequestReviewProposalRecord.Comment]? = nil
    ) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: payloadVersion,
            id: "p1",
            deduplicationKey: "d1",
            repositoryNameWithOwner: "octo/alpha",
            number: 7,
            event: "approve",
            body: nil,
            comments: comments,
            titleSnapshot: "Title",
            pendingCommentCountSnapshot: 0,
            sourceProviderID: "codex",
            sourceProcessToken: "t",
            sourceRequestID: "r",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
