import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    func testListAppliesTheSameFilterMappingTheScreenUses() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(number: 1, repo: "octo/alpha", isAuthored: true),
                    makePullRequestSummary(number: 2, repo: "octo/alpha", isReviewRequested: true),
                    makePullRequestSummary(number: 3, repo: "octo/alpha", hasReviewed: true)
                ],
                warnings: []
            )
        )

        let authored = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.listToolName,
                arguments: ["filter": .string("authored")]
            ).structuredContent
        )
        XCTAssertEqual(authored["total_count"], .number(1))

        // Reviewing covers both a pending request and an already-submitted review, matching
        // `PullRequestsViewModel`'s tab.
        let reviewing = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.listToolName,
                arguments: ["filter": .string("reviewing")]
            ).structuredContent
        )
        XCTAssertEqual(reviewing["total_count"], .number(2))

        let all = try object(await fixture.handle(PullRequestHostToolCatalog.listToolName).structuredContent)
        XCTAssertEqual(all["total_count"], .number(3))
    }

    func testListSurfacesPartialResultWarningsSoTheModelCannotClaimCompleteness() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(summaries: [], warnings: ["octo-corp is not SSO-authorized"])
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.listToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains("octo-corp is not SSO-authorized"), result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["warnings"], .array([.string("octo-corp is not SSO-authorized")]))
    }

    func testDetailReportsLinkedThreadsAndTheViewersPendingDraft() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier, pendingReviewNodeID: "PENDING_REVIEW")
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "Sources/Alpha.swift", line: 12, isPending: true)
        ]
        detail.viewerLogin = "viewer"
        fixture.pullRequests.detailResult = .success(detail)
        // The link lives on Alveary's side, which is what makes this the tool that connects a
        // pull request back to the work happening on it.
        fixture.thread.linkedPullRequests = [
            LinkedPullRequest(
                summary: makePullRequestSummary(number: identifier.number, repo: identifier.nameWithOwner),
                linkedAt: Date(timeIntervalSince1970: 900)
            )
        ]
        try fixture.modelContext.save()

        let result = await fixture.handle(PullRequestHostToolCatalog.detailToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        let threads = try array(content["linked_threads"])
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(try object(threads.first)["thread_id"], .string(fixture.conversation.id))
        let viewer = try object(content["viewer"])
        XCTAssertEqual(viewer["has_pending_review"], .bool(true))
        XCTAssertEqual(viewer["pending_comment_count"], .number(1))
    }

    func testTimelineSynthesizesTheOpenedEventGitHubDoesNotEmit() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.comments = [
            PullRequestComment(
                authorLogin: "bob",
                authorAvatarURL: nil,
                bodyMarkdown: "Looks good",
                createdAt: Date(timeIntervalSince1970: 2_000)
            )
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.timelineToolName)

        XCTAssertFalse(result.isError, result.text)
        let events = try array(try object(result.structuredContent)["events"])
        XCTAssertEqual(try object(events.first)["type"], .string("opened"))
        XCTAssertEqual(try object(events.first)["actor"], .object(["login": .string("alice")]))
        XCTAssertEqual(try object(events.last)["type"], .string("comment"))
    }

    func testTimelineWindowsToTheNewestEntriesAndReportsWhatItDropped() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.comments = (0..<5).map { index in
            PullRequestComment(
                authorLogin: "bob",
                authorAvatarURL: nil,
                bodyMarkdown: "Comment \(index)",
                createdAt: Date(timeIntervalSince1970: 2_000 + Double(index))
            )
        }
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(
            PullRequestHostToolCatalog.timelineToolName,
            arguments: ["url": .string(PullRequestHostToolFixture.url), "limit": .number(2)]
        )

        let content = try object(result.structuredContent)
        XCTAssertEqual(content["total_count"], .number(6))
        XCTAssertEqual(content["shown_count"], .number(2))
        // Newest kept, oldest-first inside the window.
        let events = try array(content["events"])
        XCTAssertEqual(try object(events.first)["body_markdown"], .string("Comment 3"))
        XCTAssertEqual(try object(events.last)["body_markdown"], .string("Comment 4"))
    }
}
