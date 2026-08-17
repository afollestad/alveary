import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A proposal lives on the conversation that opened it, so an agentic review — running in a thread
/// of its own — can only see one by asking. Its own `propose_pr_review` supersedes that proposal,
/// which is why the read has to exist before the supersede does.
extension PullRequestHostToolServiceTests {
    /// The fragment is the only thing that routes to the tool, and the carry-forward contract is
    /// what keeps a supersede from silently deleting staged comments — `HostTools/AGENTS.md` says
    /// both must stay, so a trim that drops either fails here rather than in a review that quietly
    /// loses the user's comments.
    func testTheFragmentKeepsTheCarryForwardContract() {
        let fragment = PullRequestHostToolCatalog.instructionsFragment
        XCTAssertTrue(fragment.contains("get_pr_review_proposal before proposing"))
        XCTAssertTrue(fragment.contains("a proposal that omits one deletes it"))
    }

    func testReadingReportsNoProposalWhenNoneIsPending() async throws {
        let fixture = try PullRequestHostToolFixture()

        let result = await fixture.handle(PullRequestHostToolCatalog.reviewProposalToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["has_proposal"], .bool(false))
        XCTAssertNil(content["comments"])
        XCTAssertTrue(result.text.contains("No review proposal"), result.text)
    }

    func testReadingReturnsStagedCommentsInTheShapeProposeAccepts() async throws {
        let fixture = try PullRequestHostToolFixture()
        try await fixture.stageProposal(bodies: ["First", "Second"])

        let result = await fixture.handle(PullRequestHostToolCatalog.reviewProposalToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["has_proposal"], .bool(true))
        XCTAssertEqual(content["event"], .string("comment"))
        guard case .array(let comments)? = content["comments"] else {
            return XCTFail("expected staged comments")
        }
        XCTAssertEqual(comments.count, 2)
        guard case .object(let first) = comments[0] else {
            return XCTFail("expected a comment object")
        }
        // The keys `propose_pr_review` takes, so carrying one forward is a copy.
        XCTAssertEqual(Set(first.keys), ["path", "line", "side", "body"])
        XCTAssertEqual(first["body"], .string("First"))
    }

    /// Codex persists the plain-text fallback rather than the structured content, so a model
    /// reading only the text must still be able to pass every comment back.
    func testTheTextFallbackCarriesEveryStagedComment() async throws {
        let fixture = try PullRequestHostToolFixture()
        try await fixture.stageProposal(bodies: ["First", "Second"])

        let result = await fixture.handle(PullRequestHostToolCatalog.reviewProposalToolName)

        XCTAssertTrue(result.text.contains("First"), result.text)
        XCTAssertTrue(result.text.contains("Second"), result.text)
        XCTAssertTrue(result.text.contains("Sources/Alpha.swift:1"), result.text)
    }

    /// The asking thread is usually not the holding thread — that is the whole point.
    func testAProposalOpenedByAnotherConversationIsStillReadable() async throws {
        let fixture = try PullRequestHostToolFixture()
        try await fixture.stageProposal(bodies: ["From the other thread"])
        let other = try fixture.makeSecondConversation()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.reviewProposalToolName,
            context: fixture.agentContext(conversationID: other.id)
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["has_proposal"], .bool(true))
    }

    /// One pull request, one live confirmation. Without this a second thread's proposal stands
    /// beside the card the user is looking at and the pane arbitrates between them by `createdAt`.
    func testProposingFromAnotherConversationSupersedesTheExistingCard() async throws {
        let fixture = try PullRequestHostToolFixture()
        try await fixture.stageProposal(bodies: ["Original"])
        let other = try fixture.makeSecondConversation()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: PullRequestHostToolFixture.reviewProposalArguments(bodies: ["Replacement"]),
            context: fixture.agentContext(requestID: "request-2", conversationID: other.id)
        )

        XCTAssertFalse(result.isError, result.text)
        // The first conversation's envelope is cleared, and its card resolves in its own transcript
        // rather than being orphaned.
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(
            fixture.conversation.events
                .filter { $0.type == ConversationEventRecord.hostToolOutcomeType }
                .count,
            1
        )
        let stored = try XCTUnwrap(try other.pullRequestReviewProposal())
        XCTAssertEqual(stored.stagedComments.map(\.body), ["Replacement"])
    }

    /// A proposal against a different pull request is somebody else's card.
    func testProposingDoesNotSupersedeAnotherPullRequestsProposal() async throws {
        let fixture = try PullRequestHostToolFixture()
        try await fixture.stageProposal(bodies: ["Original"], url: "https://github.com/octo/alpha/pull/99")
        let other = try fixture.makeSecondConversation()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: PullRequestHostToolFixture.reviewProposalArguments(bodies: ["Replacement"]),
            context: fixture.agentContext(requestID: "request-2", conversationID: other.id)
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
    }
}
