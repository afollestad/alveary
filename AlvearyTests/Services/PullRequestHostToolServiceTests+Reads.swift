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

    /// A thread's replies are where it says whether the point was answered or argued. Carrying
    /// only the root comment made a settled thread read as outstanding.
    func testTimelineThreadsCarryTheirWholeConversation() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(
                nodeID: "THREAD_1",
                path: "File0.swift",
                line: 1,
                isPending: false,
                bodies: ["This leaks.", "It does not — the pool owns it.", "Agreed, my mistake."]
            )
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.timelineToolName)

        let events = try array(try object(result.structuredContent)["events"]).map { try object($0) }
        let thread = try XCTUnwrap(events.first { $0["type"] == .string("review_thread") })
        XCTAssertEqual(thread["comment_count"], .number(3))
        XCTAssertEqual(thread["comments_truncated"], .bool(false))
        let bodies = try array(thread["comments"]).map { try object($0)["body_markdown"] }
        XCTAssertEqual(bodies, [.string("This leaks."), .string("It does not — the pool owns it."), .string("Agreed, my mistake.")])
        // The root is comments[0], so repeating it as body_markdown would send it twice.
        XCTAssertNil(thread["body_markdown"])
        // The text fallback is the only half Codex sees, so it carries the replies too.
        XCTAssertTrue(result.text.contains("Agreed, my mistake."), result.text)
    }

    /// Outdated threads reach the timeline already, but nothing said so — and an unlabelled
    /// outdated thread reads as feedback on code that still looks that way.
    func testTimelineFlagsOutdatedThreads() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_OLD", path: "File0.swift", line: nil, isPending: false, isOutdated: true)
        ]
        fixture.pullRequests.detailResult = .success(detail)

        let result = await fixture.handle(PullRequestHostToolCatalog.timelineToolName)

        let events = try array(try object(result.structuredContent)["events"]).map { try object($0) }
        let thread = try XCTUnwrap(events.first { $0["type"] == .string("review_thread") })
        XCTAssertEqual(thread["is_outdated"], .bool(true))
        XCTAssertTrue(result.text.contains("outdated"), result.text)
    }
}
