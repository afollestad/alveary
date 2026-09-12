import Foundation
import XCTest

@testable import Alveary

extension GitHubPullRequestsServiceTests {
    func testCollectiveFeedbackPagesEveryConnectionAndResolvedReplies() async throws {
        let shell = MockShellRunner()
        let pages = [
            feedbackPage("comments", nodes: [["id": "comment-1", "body": "First"]], next: "comments-2"),
            feedbackPage("comments", nodes: [["id": "comment-2", "body": "Second"]]),
            feedbackPage("reviews", nodes: [["id": "review-1", "state": "COMMENTED"]], next: "reviews-2"),
            feedbackPage("reviews", nodes: [["id": "pending", "state": "PENDING"]]),
            feedbackPage("reviewThreads", nodes: [[
                "id": "thread-1", "isResolved": true, "isOutdated": true,
                "comments": feedbackConnection(nodes: [["id": "reply-1", "state": "SUBMITTED"]], next: "replies-2")
            ]], next: "threads-2"),
            feedbackPage("reviewThreads", nodes: []),
            ["data": ["node": ["comments": feedbackConnection(nodes: [["id": "reply-2", "state": "SUBMITTED"]])]]]
        ]
        for page in pages {
            let data = try JSONSerialization.data(withJSONObject: page)
            await shell.enqueue(.success(pullRequestsShellResult(stdout: try XCTUnwrap(String(data: data, encoding: .utf8)))))
        }
        let service = makeGitHubPullRequestsService(shell: shell)
        let data = try await service.fetchReviewFeedback(PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((result["comments"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((result["reviews"] as? [[String: Any]])?.count, 1)
        let thread = try XCTUnwrap((result["reviewThreads"] as? [[String: Any]])?.first)
        XCTAssertEqual(thread["isResolved"] as? Bool, true)
        XCTAssertEqual(thread["isOutdated"] as? Bool, true)
        XCTAssertEqual((thread["comments"] as? [[String: Any]])?.compactMap { $0["id"] as? String }, ["reply-1", "reply-2"])
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 7)
        XCTAssertTrue(invocations[1].args.contains("cursor=comments-2"))
        XCTAssertTrue(invocations[6].args.contains("cursor=replies-2"))
    }

    func testCollectiveFeedbackRejectsRepeatedPaginationCursor() async throws {
        let page = feedbackPage("comments", nodes: [], next: "same")
        let data = try JSONSerialization.data(withJSONObject: page)
        let shell = makeUniformShellRunner(pullRequestsShellResult(stdout: try XCTUnwrap(String(data: data, encoding: .utf8))))
        await assertPullRequestsServiceThrows(.decodingFailed("Review feedback pagination did not advance")) {
            _ = try await makeGitHubPullRequestsService(shell: shell).fetchReviewFeedback(
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
            )
        }
        let count = await shell.invocations.count
        XCTAssertEqual(count, 2)
    }

    func testCollectiveFeedbackRejectsPartialGraphQLAndTruncatedResponses() async {
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let partial = makeUniformShellRunner(pullRequestsShellResult(stdout: #"{"data":{},"errors":[{"message":"incomplete"}]}"#))
        await assertPullRequestsServiceThrows(.decodingFailed("GitHub did not return complete review feedback")) {
            _ = try await makeGitHubPullRequestsService(shell: partial).fetchReviewFeedback(identifier)
        }
        let truncated = makeUniformShellRunner(pullRequestsShellResult(stdout: "{}", stdoutWasTruncated: true))
        await assertPullRequestsServiceThrows(.responseTooLarge) {
            _ = try await makeGitHubPullRequestsService(shell: truncated).fetchReviewFeedback(identifier)
        }
    }
}

private func feedbackPage(_ name: String, nodes: [[String: Any]], next: String? = nil) -> [String: Any] {
    ["data": ["repository": ["pullRequest": [name: feedbackConnection(nodes: nodes, next: next)]]]]
}

private func feedbackConnection(nodes: [[String: Any]], next: String? = nil) -> [String: Any] {
    ["nodes": nodes, "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any? ?? NSNull()]]
}
