import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    func testDiffAttachsReviewThreadsToTheFilesTheyDiscuss() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 1, isPending: false)
        ]
        fixture.pullRequests.detailResult = .success(detail)
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        let result = await fixture.handle(PullRequestHostToolCatalog.diffToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["patches_included"], .bool(true))
        let files = try array(content["files"])
        let file = try object(files.first)
        XCTAssertEqual(file["path"], .string("File0.swift"))
        XCTAssertEqual(file["thread_count"], .number(1))
        let thread = try object(try array(file["threads"]).first)
        XCTAssertEqual(thread["thread_id"], .string("THREAD_1"))
        // A submitted thread takes replies; a pending one would not.
        XCTAssertEqual(thread["can_reply"], .bool(true))
    }

    /// An outdated thread is feedback that still needs an answer, so it is listed with the flag
    /// that says to judge it against the current code — dropping it made addressing feedback
    /// silently skip whatever had been commented on before the last push.
    func testDiffListsOutdatedThreadsWithTheirFlag() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_LIVE", path: "File0.swift", line: 1, isPending: false),
            // GitHub reports no line once the anchor is gone, which is the shape that used to be
            // dropped twice over.
            makeReviewThread(nodeID: "THREAD_OLD", path: "File0.swift", line: nil, isPending: false, isOutdated: true)
        ]
        fixture.pullRequests.detailResult = .success(detail)
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        let content = try object(await fixture.handle(PullRequestHostToolCatalog.diffToolName).structuredContent)
        let file = try object(try array(content["files"]).first)

        XCTAssertEqual(file["thread_count"], .number(2))
        let threads = try array(file["threads"]).map { try object($0) }
        let outdated = try XCTUnwrap(threads.first { $0["thread_id"] == .string("THREAD_OLD") })
        XCTAssertEqual(outdated["is_outdated"], .bool(true))
        // No line to read off the patch, but the thread and its id are still there to answer.
        XCTAssertNil(outdated["line"])
        XCTAssertEqual(outdated["can_reply"], .bool(true))
    }

    /// The whole conversation, bounded. Only the first comment used to be carried anywhere, which
    /// made a settled thread read as outstanding.
    func testDiffThreadsCarryEveryCommentUpToTheCap() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        let bodies = (0..<(PullRequestHostToolLimits.maxThreadComments + 4)).map { "Reply \($0)" }
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(nodeID: "THREAD_1", path: "File0.swift", line: 1, isPending: false, bodies: bodies)
        ]
        fixture.pullRequests.detailResult = .success(detail)
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        let result = await fixture.handle(PullRequestHostToolCatalog.diffToolName)
        let content = try object(result.structuredContent)
        let thread = try object(try array(try object(try array(content["files"]).first)["threads"]).first)

        XCTAssertEqual(thread["comment_count"], .number(Double(bodies.count)))
        XCTAssertEqual(thread["comments_truncated"], .bool(true))
        let comments = try array(thread["comments"]).map { try object($0) }
        XCTAssertEqual(comments.count, PullRequestHostToolLimits.maxThreadComments)
        // Both ends survive: the root is the feedback, the tail is where the thread stands now.
        XCTAssertEqual(comments.first?["body_markdown"], .string("Reply 0"))
        XCTAssertEqual(comments.last?["body_markdown"], .string(bodies[bodies.count - 1]))
        // The text fallback marks the gap where it sits — the cap drops the middle.
        XCTAssertTrue(result.text.contains("(4 earlier replies omitted)"), result.text)
    }

    /// The per-thread cap is not a bound on its own — a response full of threads multiplies it.
    /// Threads share one response budget, going shallow rather than overflowing the wire; the
    /// per-thread floor outranks that budget, so the ceiling asserted here is the real one.
    func testManyThreadsShareOneCommentBudget() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        let bodies = (0..<8).map { "Reply \($0)" }
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = (0..<80).map { index in
            makeReviewThread(
                nodeID: "THREAD_\(index)",
                path: "File0.swift",
                line: 1,
                isPending: false,
                bodies: bodies
            )
        }
        fixture.pullRequests.detailResult = .success(detail)
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        let content = try object(await fixture.handle(PullRequestHostToolCatalog.diffToolName).structuredContent)
        let threads = try array(try object(try array(content["files"]).first)["threads"])
        let rendered = try threads.reduce(into: 0) { total, thread in
            total += try array(try object(thread)["comments"]).count
        }

        XCTAssertEqual(threads.count, 80, "every thread is still listed; only its depth gives way")
        // Far below the 80 x 8 an unshared per-thread cap would have emitted.
        XCTAssertLessThanOrEqual(
            rendered,
            max(PullRequestHostToolLimits.maxResponseThreadComments, PullRequestHostToolLimits.minThreadComments * 80)
        )
        // Every thread keeps its root and the newest reply, so none becomes unanswerable.
        for thread in threads {
            XCTAssertEqual(try array(try object(thread)["comments"]).count, PullRequestHostToolLimits.minThreadComments)
        }
    }

    /// `comments` is a page. Reporting its size as the total would tell the model a thread was
    /// fully read when the newest replies never arrived.
    func testThreadCountReportsGitHubsTotalRatherThanTheFetchedPage() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        var detail = makePullRequestDetail(id: identifier)
        detail.reviewThreads = [
            makeReviewThread(
                nodeID: "THREAD_1",
                path: "File0.swift",
                line: 1,
                isPending: false,
                bodies: ["Only one fetched."],
                totalCommentCount: 42
            )
        ]
        fixture.pullRequests.detailResult = .success(detail)
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))

        let result = await fixture.handle(PullRequestHostToolCatalog.diffToolName)
        let content = try object(result.structuredContent)
        let thread = try object(try array(try object(try array(content["files"]).first)["threads"]).first)

        XCTAssertEqual(thread["comment_count"], .number(42))
        XCTAssertEqual(thread["comments_truncated"], .bool(true))
        XCTAssertEqual(try array(thread["comments"]).count, 1)
        // The fetch drops the *newest* replies, so the text note must not call them "earlier" —
        // that would tell the model it has the thread's last word when it does not.
        XCTAssertTrue(result.text.contains("(41 newer replies not fetched)"), result.text)
    }

    func testDiffStartsWithTheInventoryAndResumesWithinAFile() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        // The response includes one full file and starts the next; its cursor must retain that position.
        fixture.pullRequests.diffResult = .success(
            makeUnifiedDiffFixture(fileCount: 3, addedLinesPerFile: 12_000)
        )

        let first = try object(await fixture.handle(PullRequestHostToolCatalog.diffToolName).structuredContent)
        XCTAssertEqual(first["total_files"], .number(3))
        // The map is complete regardless of the patch window, so the model sees the whole shape.
        XCTAssertEqual(try array(first["files"]).count, 3)
        let token = try XCTUnwrap(first["next_cursor"])
        XCTAssertNil(first["next_offset"])
        XCTAssertNotNil(first["guidance"])

        let resumed = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.diffToolName,
                arguments: ["cursor": token]
            ).structuredContent
        )
        let patched = try array(resumed["files"]).filter { file in
            (try? object(file))?["patch"] != nil
        }
        XCTAssertEqual(patched.count, 2)
        let continued = try object(patched.first)
        XCTAssertEqual(continued["path"], .string("File1.swift"))
        XCTAssertNotEqual(continued["patch_offset"], .number(0))
    }

    func testDiffRefusesAnOffsetPastTheEndRatherThanReturningNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        let result = await fixture.handle(
            PullRequestHostToolCatalog.diffToolName,
            arguments: ["url": .string(PullRequestHostToolFixture.url), "offset": .number(9)]
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.diffOffsetOutOfRange(offset: 9, fileCount: 2).localizedDescription
        )
    }

    func testDiffNamesUnknownPathsInsteadOfReturningAnEmptyResult() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        fixture.pullRequests.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))

        let result = await fixture.handle(
            PullRequestHostToolCatalog.diffToolName,
            arguments: [
                "url": .string(PullRequestHostToolFixture.url),
                "paths": .array([.string("File0.swift"), .string("Nope.swift")])
            ]
        )

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Nope.swift"), result.text)
    }

    func testDiffTooLargeToFetchReportsThatRatherThanAGenericFailure() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        fixture.pullRequests.diffResult = .failure(.responseTooLarge)

        let result = await fixture.handle(PullRequestHostToolCatalog.diffToolName)

        XCTAssertEqual(result.text, PullRequestHostToolServiceError.diffTooLarge.localizedDescription)
    }
}

/// A review thread shaped like GitHub's, with the ids the tools address it by.
///
/// `line` is optional because GitHub reports none for a thread whose anchor the head branch no
/// longer has — the common shape for an outdated thread, and the case the tools must still list.
func makeReviewThread(
    nodeID: String,
    path: String,
    line: Int?,
    isPending: Bool,
    isResolved: Bool = false,
    isOutdated: Bool = false,
    bodies: [String] = ["Consider a guard here."],
    totalCommentCount: Int? = nil
) -> PullRequestReviewThread {
    PullRequestReviewThread(
        path: path,
        line: line,
        side: .right,
        isResolved: isResolved,
        isOutdated: isOutdated,
        comments: bodies.enumerated().map { index, body in
            PullRequestComment(
                authorLogin: index == 0 ? "reviewer" : "viewer",
                authorAvatarURL: nil,
                bodyMarkdown: body,
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_500 + index)),
                databaseId: isPending ? nil : 4_242 + index,
                nodeID: "COMMENT_\(nodeID)_\(index)",
                isPending: isPending
            )
        },
        nodeID: nodeID,
        reviewNodeID: "REVIEW_1",
        totalCommentCount: totalCommentCount
    )
}
