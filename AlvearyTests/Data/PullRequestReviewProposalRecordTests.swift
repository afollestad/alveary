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

    /// A comment written before fingerprints existed still decodes and still confirms — it simply
    /// cannot relocate, which is what `ReviewProposalAnchorResolution` falls back on.
    func testAVersionTwoEnvelopeDecodesWithNoAnchorFingerprints() throws {
        let conversation = try makeConversation()
        conversation.pullRequestReviewProposalJSON = """
        {"body":"Looks good.","comments":[{"body":"Guard this.","line":4,\
        "path":"Sources/Alpha.swift","side":"RIGHT"}],\
        "createdAt":"2024-01-01T00:00:00Z","deduplicationKey":"d1",\
        "event":"approve","id":"p1","number":7,"payloadVersion":2,\
        "pendingCommentCountSnapshot":1,"repositoryNameWithOwner":"octo/alpha",\
        "sourceProcessToken":"t","sourceRequestID":"r","titleSnapshot":"Title"}
        """

        let record = try XCTUnwrap(conversation.pullRequestReviewProposal())

        XCTAssertEqual(record.payloadVersion, 2)
        let comment = try XCTUnwrap(record.stagedComments.first)
        XCTAssertEqual(comment.line, 4)
        XCTAssertNil(comment.id)
        XCTAssertNil(comment.evidence)
        XCTAssertNil(comment.anchorContent)
        XCTAssertNil(comment.anchorContext)
    }

    func testAVersionThreeEnvelopeDecodesWithAnchorFingerprintsAndNoCollectiveEvidence() throws {
        let conversation = try makeConversation()
        conversation.pullRequestReviewProposalJSON = """
        {"body":"Please fix this.","comments":[{"anchorContent":"+guard value != nil else { return }",\
        "anchorContext":["+let value = load()"],"body":"Guard this.","line":4,\
        "path":"Sources/Alpha.swift","side":"RIGHT"}],\
        "createdAt":"2024-01-01T00:00:00Z","deduplicationKey":"d1",\
        "event":"request_changes","id":"p1","number":7,"payloadVersion":3,\
        "pendingCommentCountSnapshot":1,"repositoryNameWithOwner":"octo/alpha",\
        "sourceProcessToken":"t","sourceRequestID":"r","titleSnapshot":"Title"}
        """

        let record = try XCTUnwrap(conversation.pullRequestReviewProposal())
        let comment = try XCTUnwrap(record.stagedComments.first)

        XCTAssertEqual(record.payloadVersion, 3)
        XCTAssertEqual(comment.anchorContent, "+guard value != nil else { return }")
        XCTAssertEqual(comment.anchorContext, ["+let value = load()"])
        XCTAssertNil(comment.id)
        XCTAssertNil(comment.evidence)
        XCTAssertNil(record.sourceKind)
        XCTAssertNil(record.reviewers)
    }

    func testAVersionFourEnvelopeRoundTripsCollectiveEvidenceAndProvenance() throws {
        let conversation = try makeConversation()
        let reviewers = [
            PullRequestReviewProposalRecord.Reviewer(id: "r1", providerID: "codex", modelOptionID: "gpt-5"),
            PullRequestReviewProposalRecord.Reviewer(id: "r2", providerID: "claude", modelOptionID: "sonnet")
        ]
        let evidence = PullRequestReviewProposalRecord.CommentEvidence(
            findingID: "f1",
            sourceCandidateIDs: ["r1:c1"],
            priority: 1,
            votes: [
                ReviewTeamVote(
                    voterID: "r1",
                    findingID: "f1",
                    decision: .agree,
                    priority: 1,
                    rationale: "The failure is reachable."
                )
            ],
            reviewers: reviewers
        )
        let record = makeCollectiveRecord(reviewers: reviewers, evidence: evidence)

        try conversation.storePullRequestReviewProposal(record)
        let decoded = try XCTUnwrap(conversation.pullRequestReviewProposal())

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.stagedComments.first?.evidence, evidence)
        XCTAssertEqual(decoded.sourceKind, .collectiveReview)
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

    func testRemovingAStagedCommentKeepsEverythingElseIntact() throws {
        let comments = [
            PullRequestReviewProposalRecord.Comment(path: "A.swift", line: 3, side: "RIGHT", body: "First"),
            PullRequestReviewProposalRecord.Comment(path: "B.swift", line: 9, side: "LEFT", body: "Second")
        ]
        let record = makeRecord(comments: comments)

        let updated = try XCTUnwrap(record.removingComment(at: 0))

        XCTAssertEqual(updated.stagedComments, [comments[1]])
        // The envelope is otherwise the same proposal, including the version it was written at.
        XCTAssertEqual(updated.id, record.id)
        XCTAssertEqual(updated.deduplicationKey, record.deduplicationKey)
        XCTAssertEqual(updated.payloadVersion, record.payloadVersion)
        XCTAssertEqual(updated.pendingCommentCountSnapshot, record.pendingCommentCountSnapshot)
        XCTAssertEqual(updated.createdAt, record.createdAt)
    }

    /// A comment-free proposal is written with a nil `comments`, so emptying one has to land in the
    /// same shape rather than storing `[]`.
    func testRemovingTheLastStagedCommentClearsTheList() throws {
        let conversation = try makeConversation()
        let record = makeRecord(comments: [
            PullRequestReviewProposalRecord.Comment(path: "A.swift", line: 3, side: "RIGHT", body: "Only")
        ])

        let updated = try XCTUnwrap(record.removingComment(at: 0))
        try conversation.storePullRequestReviewProposal(updated)

        XCTAssertNil(updated.comments)
        XCTAssertEqual(try conversation.pullRequestReviewProposal()?.stagedComments, [])
    }

    func testRemovingAnOutOfRangeCommentRewritesNothing() {
        let record = makeRecord(comments: [
            PullRequestReviewProposalRecord.Comment(path: "A.swift", line: 3, side: "RIGHT", body: "Only")
        ])

        XCTAssertNil(record.removingComment(at: 1))
        XCTAssertNil(makeRecord().removingComment(at: 0))
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

    func makeCollectiveRecord(
        reviewers: [PullRequestReviewProposalRecord.Reviewer],
        evidence: PullRequestReviewProposalRecord.CommentEvidence
    ) -> PullRequestReviewProposalRecord {
        PullRequestReviewProposalRecord(
            payloadVersion: 4,
            id: "collective-proposal",
            deduplicationKey: "collective-review:run-1",
            repositoryNameWithOwner: "octo/alpha",
            number: 7,
            event: "request_changes",
            body: "Please address this.",
            comments: [
                PullRequestReviewProposalRecord.Comment(
                    id: "collective:run-1:f1",
                    path: "A.swift",
                    line: 3,
                    side: "RIGHT",
                    body: "**[P1]** Guard this.",
                    evidence: evidence,
                    anchorContent: "+guard value != nil else { return }",
                    anchorContext: ["+let value = load()"]
                )
            ],
            titleSnapshot: "Title",
            pendingCommentCountSnapshot: 0,
            sourceProviderID: nil,
            sourceProcessToken: nil,
            sourceRequestID: nil,
            sourceKind: .collectiveReview,
            sourceRunID: "run-1",
            sourceResultHash: "result-hash",
            reviewedBaseOID: "base",
            reviewedHeadOID: "head",
            reviewers: reviewers,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
