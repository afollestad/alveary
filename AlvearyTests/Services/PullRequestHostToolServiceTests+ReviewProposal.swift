import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    func testProposingAReviewSubmitsNothingAndOpensAConfirmation() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("pending_confirmation"))
        XCTAssertEqual(content["proposal_id"], .string(PullRequestHostToolFixture.proposalID))
        // Nothing may reach GitHub before the user confirms.
        XCTAssertTrue(fixture.pullRequests.submittedReviews.isEmpty)
        XCTAssertTrue(fixture.pullRequests.submittedPendingReviews.isEmpty)
        XCTAssertTrue(result.text.contains("Nothing has been submitted"), result.text)
        XCTAssertNotNil(try fixture.conversation.pullRequestReviewProposal())
    }

    func testApprovingYourOwnPullRequestIsRefusedBeforeTheUserIsAsked() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        // `makePullRequestDetail` authors as "alice"; making the viewer the author is the case
        // GitHub rejects.
        detail.viewerLogin = "alice"
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.cannotReviewOwnPullRequest.localizedDescription
        )
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
    }

    func testRequestingChangesWithoutABodyIsRefused() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: [
                "url": .string(PullRequestHostToolFixture.url),
                "event": .string("request_changes")
            ]
        )

        XCTAssertEqual(result.text, PullRequestHostToolServiceError.reviewBodyRequired.localizedDescription)
    }

    func testAMergedPullRequestCanNoLongerBeReviewed() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier, status: .merged)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.pullRequestNotReviewable(status: "merged").localizedDescription
        )
    }

    func testAnExactRetryReplaysTheProposalRatherThanOpeningASecond() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)

        let first = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)
        let replay = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        XCTAssertEqual(replay.text, first.text)
        XCTAssertEqual(
            try object(replay.structuredContent)["proposal_id"],
            .string(PullRequestHostToolFixture.proposalID)
        )
    }

    func testAProposalForADifferentPullRequestIsRefusedWhileOneIsPending() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        _ = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        let other = try XCTUnwrap(PullRequestIdentifier(nameWithOwner: "octo/beta", number: 9))
        var otherDetail = makePullRequestDetail(id: other)
        otherDetail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(otherDetail)
        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: [
                "url": .string("https://github.com/octo/beta/pull/9"),
                "event": .string("approve")
            ],
            context: fixture.agentContext(requestID: "request-2")
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("octo/alpha#7"), result.text)
    }

    func testARevisedProposalForTheSamePullRequestSupersedesTheOldOne() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        _ = await fixture.handle(PullRequestHostToolCatalog.proposeReviewToolName)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: [
                "url": .string(PullRequestHostToolFixture.url),
                "event": .string("comment"),
                "body": .string("One more thing.")
            ],
            context: fixture.agentContext(requestID: "request-2")
        )

        XCTAssertFalse(result.isError, result.text)
        let stored = try XCTUnwrap(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(stored.event, "comment")
        // The superseded proposal records a rejection so the transcript never shows two live
        // confirmations for one review.
        let markers = fixture.conversation.events.filter {
            $0.type == ConversationEventRecord.hostToolOutcomeType
        }
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(
            markers.first?.toolName,
            HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName)
        )
    }

    func testAMissingRequestIdentityIsRefusedSoRetriesStayDetectable() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            context: fixture.agentContext(requestID: nil)
        )

        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.missingRequestIdentity.localizedDescription
        )
    }
}
