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

    func testStagedCommentsAreStoredInTheEnvelopeAndReachGitHubNowhere() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        fixture.stubAlphaDiff()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: PullRequestHostToolFixture.reviewProposalArguments(bodies: ["First", "Second"])
        )

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["comment_count"], .number(2))
        // The comments exist only in the stored envelope until the user confirms.
        XCTAssertTrue(fixture.pullRequests.addedPendingComments.isEmpty)
        XCTAssertTrue(fixture.pullRequests.createdPendingReviewNodeIDs.isEmpty)
        let stored = try XCTUnwrap(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(stored.stagedComments.map(\.body), ["First", "Second"])
        XCTAssertEqual(stored.stagedComments.first?.side, "RIGHT")
        XCTAssertTrue(result.text.contains("staged in Alveary"), result.text)
    }

    /// A `comment` verdict needs something to publish; comments carried by this very call count.
    func testACommentVerdictIsSatisfiedByTheCallsOwnComments() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        fixture.stubAlphaDiff()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: PullRequestHostToolFixture.reviewProposalArguments(event: "comment", bodies: ["First"])
        )

        XCTAssertFalse(result.isError, result.text)
    }

    /// GitHub anchors review comments to diff lines, so a miss is refused at propose time — where
    /// the model can fix it — never at confirmation, after the user already agreed.
    func testACommentAnchoredOffTheDiffIsRefusedByItsIndex() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        // The diff carries lines 1 and 2; the second comment anchors at line 3.
        fixture.stubAlphaDiff(lineCount: 2)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: PullRequestHostToolFixture.reviewProposalArguments(bodies: ["First", "Second", "Third"])
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("comments[2]"), result.text)
        XCTAssertTrue(result.text.contains("Sources/Alpha.swift:3"), result.text)
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
    }

    /// A context line carries both an old and a new number, so a raw old-number comparison used to
    /// accept a LEFT anchor on one. The pane anchors a context line RIGHT only, so such a comment
    /// validated here and then rendered nowhere — refusing it keeps a confirmable proposal
    /// renderable.
    func testALeftAnchorOnAContextLineIsRefused() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        fixture.stubAlphaDiffWithContextAndDeletion()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: [
                "url": .string(PullRequestHostToolFixture.url),
                "event": .string("comment"),
                "comments": .array([
                    PullRequestHostToolFixture.reviewComment(line: 1, side: "LEFT", body: "On context")
                ])
            ]
        )

        XCTAssertTrue(result.isError, result.text)
        XCTAssertTrue(result.text.contains("comments[0]"), result.text)
        XCTAssertNil(try fixture.conversation.pullRequestReviewProposal())
    }

    /// The sides the pane can actually draw: LEFT on a deleted line, RIGHT on a context or added
    /// one. Guards the tightening above against over-refusing.
    func testAnchorsThePaneCanDrawStillPass() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        fixture.stubAlphaDiffWithContextAndDeletion()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.proposeReviewToolName,
            arguments: [
                "url": .string(PullRequestHostToolFixture.url),
                "event": .string("comment"),
                "comments": .array([
                    PullRequestHostToolFixture.reviewComment(line: 2, side: "LEFT", body: "On deletion"),
                    PullRequestHostToolFixture.reviewComment(line: 1, side: "RIGHT", body: "On context"),
                    PullRequestHostToolFixture.reviewComment(line: 2, side: "RIGHT", body: "On addition")
                ])
            ]
        )

        XCTAssertFalse(result.isError, result.text)
        let record = try XCTUnwrap(try fixture.conversation.pullRequestReviewProposal())
        XCTAssertEqual(record.stagedComments.count, 3)
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
