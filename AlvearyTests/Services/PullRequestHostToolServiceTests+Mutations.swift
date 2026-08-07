import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
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
