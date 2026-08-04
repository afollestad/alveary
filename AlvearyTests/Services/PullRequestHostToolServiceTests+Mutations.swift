import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    func testAddingReviewCommentsAdoptsTheViewersExistingDraft() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, pendingReviewNodeID: "EXISTING_DRAFT")
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName)

        XCTAssertFalse(result.isError, result.text)
        // GitHub allows one pending review per viewer, so an existing draft must be reused.
        XCTAssertTrue(fixture.pullRequests.createdPendingReviewNodeIDs.isEmpty)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.first?.reviewNodeID, "EXISTING_DRAFT")
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("added"))
        // The message has to say the comments are not published, or the model will report them as such.
        XCTAssertTrue(result.text.contains("nothing is published"), result.text)
    }

    func testAddingReviewCommentsOpensADraftWhenNoneExists() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))

        let result = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fixture.pullRequests.createdPendingReviewNodeIDs, ["PR_7"])
    }

    func testABatchWritesEveryCommentIntoOneAdoptedDraft() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier, pendingReviewNodeID: "EXISTING_DRAFT")
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "Sources/Alpha.swift", line: 3, isPending: true)
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addReviewCommentsToolName,
            arguments: PullRequestHostToolFixture.reviewCommentArguments(bodies: ["First", "Second", "Third"])
        )

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.map(\.body), ["First", "Second", "Third"])
        // One draft and one detail read serve the whole batch.
        XCTAssertTrue(fixture.pullRequests.createdPendingReviewNodeIDs.isEmpty)
        XCTAssertEqual(fixture.pullRequests.detailCallCount, 1)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("added"))
        XCTAssertEqual(content["added_count"], .number(3))
        // The draft already held one pending comment before this call.
        XCTAssertEqual(content["pending_comment_count"], .number(4))
        let rows = try array(content["comments"]).map { try object($0) }
        XCTAssertEqual(rows.map { $0["status"] }, Array(repeating: .string("added"), count: 3))
        XCTAssertEqual(rows.first?["thread_id"], .string("PENDING_THREAD_First"))
    }

    func testABatchStopsAtTheFirstFailureAndReportsWhatLanded() async throws {
        let fixture = try PullRequestHostToolFixture()
        try fixture.failReviewCommentAfterTheFirst()

        let result = await fixture.handle(
            PullRequestHostToolCatalog.addReviewCommentsToolName,
            arguments: PullRequestHostToolFixture.reviewCommentArguments(bodies: ["First", "Second", "Third"])
        )

        // A partial batch mutated GitHub and carries per-comment detail, so it is not an error result.
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.map(\.body), ["First", "Second"])
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("partial"))
        XCTAssertEqual(content["added_count"], .number(1))
        XCTAssertEqual(content["pending_comment_count"], .number(1))
        let rows = try array(content["comments"]).map { try object($0) }
        XCTAssertEqual(
            rows.map { $0["status"] },
            [.string("added"), .string("failed"), .string("skipped")]
        )
        // The model needs the failing anchor to know which comments still need a call.
        XCTAssertTrue(result.text.contains("Sources/Beta.swift:2"), result.text)
        XCTAssertTrue(result.text.contains("nothing is published"), result.text)
    }

    func testAPartialBatchReplaysRatherThanPostingWhatAlreadyLandedAgain() async throws {
        let fixture = try PullRequestHostToolFixture()
        try fixture.failReviewCommentAfterTheFirst()
        let arguments = PullRequestHostToolFixture.reviewCommentArguments(bodies: ["First", "Second", "Third"])

        let first = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName, arguments: arguments)
        let replay = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName, arguments: arguments)

        XCTAssertEqual(replay.text, first.text)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.count, 2, "the replay re-posted what had landed")
        let content = try object(replay.structuredContent)
        XCTAssertEqual(content["status"], .string("partial"))
        let rows = try array(content["comments"]).map { try object($0) }
        XCTAssertEqual(
            rows.map { $0["status"] },
            [.string("added"), .string("failed"), .string("skipped")]
        )

        // Calling again with only the comments that never landed is a different payload, so it acts.
        let followUp = await fixture.handle(
            PullRequestHostToolCatalog.addReviewCommentsToolName,
            arguments: PullRequestHostToolFixture.reviewCommentArguments(bodies: ["Second", "Third"])
        )
        XCTAssertFalse(followUp.isError, followUp.text)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.count, 4)
    }

    func testABatchThatWritesNothingIsAnErrorAndKeepsNoReceipt() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, pendingReviewNodeID: "EXISTING_DRAFT")
        )
        fixture.pullRequests.addPendingCommentResults = [.failure(.transport("offline"))]

        let failed = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName)

        XCTAssertTrue(failed.isError)
        XCTAssertEqual(try object(failed.structuredContent)["status"], .string("error"))

        // Nothing was written, so nothing was receipted: the same call may be made again.
        let retry = await fixture.handle(PullRequestHostToolCatalog.addReviewCommentsToolName)
        XCTAssertFalse(retry.isError, retry.text)
        XCTAssertEqual(fixture.pullRequests.addedPendingComments.count, 2)
    }

    func testAnExactRetryReplaysItsReceiptInsteadOfCommentingTwice() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, pendingReviewNodeID: "EXISTING_DRAFT")
        )

        let first = await fixture.handle(PullRequestHostToolCatalog.commentToolName)
        let replay = await fixture.handle(PullRequestHostToolCatalog.commentToolName)

        XCTAssertFalse(replay.isError, replay.text)
        XCTAssertEqual(fixture.pullRequests.addedIssueComments.count, 1)
        XCTAssertEqual(replay.text, first.text)
    }

    func testReplyingToAPendingThreadIsRefusedBecauseGitHubTakesNoReplyYet() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "Sources/Alpha.swift", line: 3, isPending: true)
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.replyToThreadToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.reviewThreadPendingNoReplies.localizedDescription
        )
        XCTAssertTrue(fixture.pullRequests.threadReplies.isEmpty)
    }

    func testReplyingToAnUnknownThreadPointsAtTheReadToolsRatherThanFailingOpaquely() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))

        let result = await fixture.handle(PullRequestHostToolCatalog.replyToThreadToolName)

        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.reviewThreadNotFound(threadID: "THREAD_1").localizedDescription
        )
    }

    func testResolvingAnAlreadyResolvedThreadIsASuccessThatChangesNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(
                nodeID: "THREAD_1",
                path: "Sources/Alpha.swift",
                line: 3,
                isPending: false,
                isResolved: true
            )
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.resolveThreadToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_resolved"))
        XCTAssertTrue(fixture.pullRequests.threadResolutions.isEmpty)
    }

    func testUnresolvingFlipsTheSameThreadTheOtherWay() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(
                nodeID: "THREAD_1",
                path: "Sources/Alpha.swift",
                line: 3,
                isPending: false,
                isResolved: true
            )
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.unresolveThreadToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("unresolved"))
        XCTAssertEqual(
            fixture.pullRequests.threadResolutions,
            [.init(threadID: "THREAD_1", resolved: false)]
        )
    }

    func testAGitHubFailureReachesTheModelAsAReachabilityMessage() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.detailResult = .failure(.notAuthenticated)

        let result = await fixture.handle(PullRequestHostToolCatalog.detailToolName)

        XCTAssertTrue(result.isError)
        XCTAssertNotEqual(
            result.text,
            PullRequestHostToolServiceError.persistenceFailure.localizedDescription,
            "a GitHub failure must not collapse into the generic host error"
        )
        XCTAssertTrue(result.text.contains("could not reach"), result.text)
    }
}
