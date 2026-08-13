import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    /// The question "what needs my review" is answered by `reviewing`, so an already-reviewed pull
    /// request must not appear there — the screen separates the two into sections, which a flat
    /// tool result cannot do.
    func testEachFilterListsOneInvolvementAndReviewingExcludesWhatWasAlreadyReviewed() async throws {
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

        let reviewing = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.listToolName,
                arguments: ["filter": .string("reviewing")]
            ).structuredContent
        )
        XCTAssertEqual(reviewing["total_count"], .number(1))
        XCTAssertEqual(try listedNumbers(reviewing), [2])

        let reviewed = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.listToolName,
                arguments: ["filter": .string("reviewed")]
            ).structuredContent
        )
        XCTAssertEqual(reviewed["total_count"], .number(1))
        XCTAssertEqual(try listedNumbers(reviewed), [3])

        let all = try object(await fixture.handle(PullRequestHostToolCatalog.listToolName).structuredContent)
        XCTAssertEqual(all["total_count"], .number(3))
    }

    /// Every fetched row reaches `link_pr`'s fetch-skipping handoff — including rows the limit
    /// drops, because the fetch proved them reachable and that proof is all the handoff carries.
    func testListingHandsEveryFetchedRowToTheSummaryHandoff() async throws {
        let fixture = try PullRequestHostToolFixture()
        let newer = makePullRequestSummary(
            number: 1,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isReviewRequested: true
        )
        let older = makePullRequestSummary(
            number: 2,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isReviewRequested: true
        )
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(summaries: [newer, older], warnings: [])
        )

        let content = try object(await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("reviewing"), "limit": .number(1)]
        ).structuredContent)

        XCTAssertEqual(try listedNumbers(content), [1])
        XCTAssertEqual(fixture.summaryHandoff.summary(for: newer.id), newer)
        XCTAssertEqual(fixture.summaryHandoff.summary(for: older.id), older)
    }

    /// Each review scope is one GitHub search, which is the whole reason the filter picks buckets
    /// rather than narrowing a merged set after the fact.
    func testEachReviewFilterFetchesOnlyItsOwnBucket() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(PullRequestListResult(summaries: [], warnings: []))

        _ = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("reviewing")]
        )
        _ = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("reviewed")]
        )

        XCTAssertEqual(fixture.pullRequests.listRequests.map(\.buckets), [[.reviewRequested], [.reviewed]])
    }

    /// GitHub clears the review request when a review is submitted, so a pull request carrying both
    /// flags was requested *again* afterwards and is genuinely waiting — the same rule the screen's
    /// "Pending review" section follows.
    func testAReRequestedPullRequestStillNeedsReview() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(
                        number: 4,
                        repo: "octo/alpha",
                        isReviewRequested: true,
                        hasReviewed: true
                    )
                ],
                warnings: []
            )
        )

        let reviewing = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.listToolName,
                arguments: ["filter": .string("reviewing")]
            ).structuredContent
        )

        XCTAssertEqual(try listedNumbers(reviewing), [4])
    }

    /// The text half carries no `involvement` object, so without the phrase a Codex-style consumer
    /// reading a `filter: "all"` result cannot tell what awaits review from what already had it.
    func testTheTextFallbackSaysWhichRowsAwaitReview() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(number: 2, repo: "octo/alpha", title: "Awaits", isReviewRequested: true),
                    makePullRequestSummary(number: 3, repo: "octo/alpha", title: "Done", hasReviewed: true),
                    makePullRequestSummary(number: 1, repo: "octo/alpha", title: "Mine", isAuthored: true)
                ],
                warnings: []
            )
        )

        let text = await fixture.handle(PullRequestHostToolCatalog.listToolName).text

        let rows = text.split(separator: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(rows.count, 3, text)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.contains("#2") }).hasSuffix(", review requested)"), text)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.contains("#3") }).hasSuffix(", already reviewed)"), text)
        // An authored-only row says nothing extra: its author is already on the line.
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.contains("#1") }).contains("review"), text)
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

    /// The no-arguments call is the one every model makes, so what reaches the service for it must
    /// stay byte-for-byte what it always was.
    func testAnUnargumentedListCallFetchesExactlyWhatItAlwaysDid() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(PullRequestListResult(summaries: [], warnings: []))

        _ = await fixture.handle(PullRequestHostToolCatalog.listToolName)

        let request = try XCTUnwrap(fixture.pullRequests.listRequests.first)
        XCTAssertEqual(request.buckets, Set(PullRequestInvolvementBucket.allCases))
        XCTAssertEqual(request.status, .open)
        XCTAssertEqual(request.options, .firstPage)
    }

    func testListOptionsReachTheService() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(PullRequestListResult(summaries: [], warnings: []))

        _ = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: [
                "filter": .string("authored"),
                "status": .string("merged"),
                "limit": .number(5),
                "updated_after": .string("2026-01-01")
            ]
        )

        let request = try XCTUnwrap(fixture.pullRequests.listRequests.first)
        XCTAssertEqual(request.buckets, [.authored])
        XCTAssertEqual(request.status, .merged)
        XCTAssertEqual(request.options.pageSize, 5)
        XCTAssertEqual(request.options.updatedAfter, Date(timeIntervalSince1970: 1_767_225_600))
    }

    /// A text-only consumer never sees `structuredContent`, so a cursor that rode only there would
    /// leave it unable to ask for page two.
    func testTheNextCursorReachesBothHalvesOfTheResultAndRoundTrips() async throws {
        let fixture = try PullRequestHostToolFixture()
        let summaries = (1...3).map { makePullRequestSummary(number: $0, isAuthored: true) }
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summariesByBucket: [.authored: summaries],
                warnings: [],
                pageInfoByBucket: [
                    .authored: PullRequestListPageInfo(
                        endCursor: "a3",
                        hasNextPage: true,
                        rowCursors: ["a1", "a2", "a3"]
                    )
                ]
            )
        )

        let first = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("authored"), "limit": .number(2)]
        )

        let content = try object(first.structuredContent)
        let cursorValue = try XCTUnwrap(content["next_cursor"])
        guard case .string(let cursor) = cursorValue else {
            return XCTFail("next_cursor must be a string")
        }
        XCTAssertTrue(first.text.contains(cursor), first.text)
        XCTAssertTrue(first.text.contains("More results are available"), first.text)
        // Two of three rows went out, so the next page resumes at the second row's cursor rather
        // than at the page boundary, which would have skipped the third.
        XCTAssertEqual(
            try PullRequestListCursorToken.decoded(from: cursor, path: "arguments").cursors,
            [.authored: "a2"]
        )

        _ = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["cursor": .string(cursor)]
        )

        let resumed = try XCTUnwrap(fixture.pullRequests.listRequests.last)
        XCTAssertEqual(resumed.buckets, [.authored])
        XCTAssertEqual(resumed.options.cursors, [.authored: "a2"])
        XCTAssertEqual(resumed.options.pageSize, 2)
    }

    func testNoCursorComesBackWhenEveryBucketIsDrained() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summariesByBucket: [.authored: [makePullRequestSummary(number: 1, isAuthored: true)]],
                warnings: [],
                pageInfoByBucket: [.authored: PullRequestListPageInfo(
                    endCursor: "a1",
                    hasNextPage: false,
                    rowCursors: ["a1"]
                )]
            )
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("authored")]
        )

        XCTAssertNil(try object(result.structuredContent)["next_cursor"])
        XCTAssertFalse(result.text.contains("More results are available"), result.text)
    }

    /// The status has to be visible in the text half now that it is settable, but the parenthetical
    /// stays the filter alone — the transcript card finds the filter by matching it.
    func testTheHeaderNamesTheStatusWithoutDisturbingTheFilterParenthetical() async throws {
        let fixture = try PullRequestHostToolFixture()
        fixture.pullRequests.listResult = .success(
            PullRequestListResult(
                summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
                warnings: []
            )
        )

        let result = await fixture.handle(
            PullRequestHostToolCatalog.listToolName,
            arguments: ["filter": .string("authored"), "status": .string("merged")]
        )

        XCTAssertTrue(result.text.hasPrefix("Found 1 merged pull request (authored)"), result.text)
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

    /// The rows a list call actually emitted, so a filter assertion can name them instead of
    /// trusting a count that several fixtures could satisfy.
    func listedNumbers(_ content: [String: AgentCLIKit.JSONValue]) throws -> [Int] {
        try array(content["pull_requests"]).compactMap { row in
            guard case .number(let number)? = try object(row)["number"] else {
                return nil
            }
            return Int(number)
        }
    }
}
