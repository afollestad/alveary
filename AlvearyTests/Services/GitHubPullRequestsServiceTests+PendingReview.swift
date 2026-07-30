import XCTest

@testable import Alveary

/// The pending-review mutations: all GraphQL, all addressed by node id, none
/// retried. These are what make an inline comment show up on github.com as soon
/// as it is written instead of only at submit time.
extension GitHubPullRequestsServiceTests {
    private static let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    /// Pulls the `-f name=value` pairs out of a `gh api graphql` invocation.
    private func graphQLArguments(_ args: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for (index, arg) in args.enumerated() where arg == "-f" || arg == "-F" {
            guard let pair = args[safe: index + 1],
                  let separator = pair.firstIndex(of: "=") else {
                continue
            }
            values[String(pair[pair.startIndex..<separator])] = String(pair[pair.index(after: separator)...])
        }
        return values
    }

    func testCreatePendingReviewOmitsEventAndReturnsTheReviewID() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: #"{"data":{"addPullRequestReview":{"pullRequestReview":{"id":"PRR_draft"}}}}"#
        )))
        let service = makeGitHubPullRequestsService(shell: shell)

        let reviewID = try await service.createPendingReview(pullRequestNodeID: "PR_7")

        XCTAssertEqual(reviewID, "PRR_draft")
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(Array(invocation.args.prefix(2)), ["api", "graphql"])
        let arguments = graphQLArguments(invocation.args)
        XCTAssertEqual(arguments["pullRequestId"], "PR_7")
        let query = try XCTUnwrap(arguments["query"])
        XCTAssertTrue(query.contains("addPullRequestReview"))
        // Omitting `event` is the whole point: it leaves the review PENDING.
        XCTAssertFalse(query.contains("event"))
    }

    func testCreatePendingReviewWithoutAnIDFails() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(
            stdout: #"{"data":{"addPullRequestReview":{"pullRequestReview":null}}}"#
        )))
        let service = makeGitHubPullRequestsService(shell: shell)

        do {
            _ = try await service.createPendingReview(pullRequestNodeID: "PR_7")
            XCTFail("Expected a transport failure")
        } catch let error as PullRequestsServiceError {
            guard case .transport = error else {
                return XCTFail("Expected .transport, got \(error)")
            }
        } catch {
            XCTFail("Expected a PullRequestsServiceError, got \(error)")
        }
    }

    func testAddPendingReviewCommentSendsTheAnchorAndDecodesTheThread() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: Self.addThreadResponse)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let thread = try await service.addPendingReviewComment(
            reviewNodeID: "PRR_draft",
            path: "Sources/Parser.swift",
            line: 12,
            side: .left,
            body: "Deleted line note"
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        let arguments = graphQLArguments(invocation.args)
        XCTAssertEqual(arguments["reviewId"], "PRR_draft")
        XCTAssertEqual(arguments["path"], "Sources/Parser.swift")
        XCTAssertEqual(arguments["body"], "Deleted line note")
        XCTAssertEqual(arguments["side"], "LEFT")
        // `line` is an Int in the schema, so it must travel as `-F`, not `-f`.
        XCTAssertTrue(invocation.args.contains("-F"))
        XCTAssertEqual(arguments["line"], "12")

        // The returned thread is shaped exactly like a fetched one, so it can
        // replace the optimistic placeholder in place.
        XCTAssertEqual(thread.nodeID, "PRT_draft")
        XCTAssertEqual(thread.path, "Sources/Parser.swift")
        XCTAssertEqual(thread.side, .left)
        XCTAssertEqual(thread.reviewNodeID, "PRR_draft")
        XCTAssertTrue(thread.isPending)
        let comment = try XCTUnwrap(thread.comments.first)
        XCTAssertEqual(comment.nodeID, "PRRC_draft")
        XCTAssertEqual(comment.databaseId, 988)
        XCTAssertTrue(comment.isPending)
        XCTAssertTrue(comment.viewerCanUpdate)
        XCTAssertTrue(comment.viewerCanDelete)
    }

    func testUpdateAndDeletePendingCommentUseNodeIDs() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.updatePendingReviewComment(commentNodeID: "PRRC_draft", body: "Revised")
        try await service.deletePendingReviewComment(commentNodeID: "PRRC_draft")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        let update = graphQLArguments(invocations[0].args)
        XCTAssertEqual(update["commentId"], "PRRC_draft")
        XCTAssertEqual(update["body"], "Revised")
        XCTAssertTrue(try XCTUnwrap(update["query"]).contains("updatePullRequestReviewComment"))

        let delete = graphQLArguments(invocations[1].args)
        XCTAssertEqual(delete["commentId"], "PRRC_draft")
        XCTAssertTrue(try XCTUnwrap(delete["query"]).contains("deletePullRequestReviewComment"))
        // Never the REST endpoint submitted comments use.
        XCTAssertFalse(invocations.contains { $0.args.contains("pulls/comments/988") })
    }

    func testDeletePendingReviewDiscardsTheDraft() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.deletePendingReview(reviewNodeID: "PRR_draft")

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        let arguments = graphQLArguments(invocation.args)
        XCTAssertEqual(arguments["reviewId"], "PRR_draft")
        XCTAssertTrue(try XCTUnwrap(arguments["query"]).contains("deletePullRequestReview"))
    }

    func testSubmitPendingReviewCarriesTheVerdictAndBody() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "{}")))
        let service = makeGitHubPullRequestsService(shell: shell)

        try await service.submitPendingReview(
            reviewNodeID: "PRR_draft",
            event: .requestChanges,
            body: "Please fix the parser edge case."
        )

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        let arguments = graphQLArguments(invocation.args)
        XCTAssertEqual(arguments["reviewId"], "PRR_draft")
        XCTAssertEqual(arguments["event"], "REQUEST_CHANGES")
        XCTAssertEqual(arguments["body"], "Please fix the parser edge case.")
        XCTAssertTrue(try XCTUnwrap(arguments["query"]).contains("submitPullRequestReview"))
    }

    func testPendingMutationsDoNotRetryTransientFailures() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stderr: "HTTP 502", exitCode: 1)))
        let service = makeGitHubPullRequestsService(shell: shell)

        do {
            try await service.deletePendingReviewComment(commentNodeID: "PRRC_draft")
            XCTFail("Expected the 502 to surface")
        } catch {
            // Expected: mutations are not idempotent, so they never retry.
        }
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 1)
    }

    func testDetailSurfacesThePendingReviewAndItsComments() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: PullRequestsServiceFixtures.detail)))
        let service = makeGitHubPullRequestsService(shell: shell)

        let detail = try await service.fetchDetail(Self.id)

        XCTAssertEqual(detail.pendingReviewNodeID, "PRR_draft")
        // The viewer's own draft is not activity: it must never render as a
        // review card or a reviewer verdict.
        XCTAssertEqual(detail.reviews.map(\.nodeID), ["PRR_1"])
        XCTAssertEqual(detail.pendingCommentCount, 1)
        let pending = try XCTUnwrap(detail.pendingReviewThreads.first)
        XCTAssertEqual(pending.nodeID, "PRT_draft")
        XCTAssertEqual(pending.side, .left)
        XCTAssertTrue(pending.isPending)
        // A pending thread takes no replies until the review is submitted.
        XCTAssertNil(pending.replyTargetCommentID)
        // Submitted threads are unaffected.
        XCTAssertEqual(detail.reviewThreads.first?.isPending, false)
        XCTAssertEqual(detail.reviewThreads.first?.replyTargetCommentID, 987)
    }

    private static let addThreadResponse = """
    {
      "data": {
        "addPullRequestReviewThread": {
          "thread": {
            "id": "PRT_draft",
            "path": "Sources/Parser.swift",
            "line": 12,
            "diffSide": "LEFT",
            "isResolved": false,
            "isOutdated": false,
            "comments": {
              "nodes": [
                {
                  "id": "PRRC_draft",
                  "databaseId": 988,
                  "viewerCanUpdate": true,
                  "viewerCanDelete": true,
                  "state": "PENDING",
                  "pullRequestReview": { "id": "PRR_draft" },
                  "author": { "login": "viewer", "avatarUrl": null },
                  "body": "Deleted line note",
                  "createdAt": "2026-07-03T09:00:00Z",
                  "reactionGroups": []
                }
              ]
            }
          }
        }
      }
    }
    """
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
