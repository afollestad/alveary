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

    func testDiffPagesByFileAndAlwaysListsEveryFile() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
        // Each file's patch is far larger than the whole budget, so only one fits per call.
        fixture.pullRequests.diffResult = .success(
            makeUnifiedDiffFixture(fileCount: 3, addedLinesPerFile: 12_000)
        )

        let first = try object(await fixture.handle(PullRequestHostToolCatalog.diffToolName).structuredContent)
        XCTAssertEqual(first["total_files"], .number(3))
        // The map is complete regardless of the patch window, so the model sees the whole shape.
        XCTAssertEqual(try array(first["files"]).count, 3)
        XCTAssertEqual(first["next_offset"], .number(1))
        XCTAssertNotNil(first["guidance"])

        let resumed = try object(
            await fixture.handle(
                PullRequestHostToolCatalog.diffToolName,
                arguments: ["url": .string(PullRequestHostToolFixture.url), "offset": .number(1)]
            ).structuredContent
        )
        let patched = try array(resumed["files"]).filter { file in
            (try? object(file))?["patch"] != nil
        }
        XCTAssertEqual(patched.count, 1)
        XCTAssertEqual(try object(patched.first)["path"], .string("File1.swift"))
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
func makeReviewThread(
    nodeID: String,
    path: String,
    line: Int,
    isPending: Bool,
    isResolved: Bool = false
) -> PullRequestReviewThread {
    PullRequestReviewThread(
        path: path,
        line: line,
        side: .right,
        isResolved: isResolved,
        isOutdated: false,
        comments: [
            PullRequestComment(
                authorLogin: "viewer",
                authorAvatarURL: nil,
                bodyMarkdown: "Consider a guard here.",
                createdAt: Date(timeIntervalSince1970: 1_500),
                databaseId: isPending ? nil : 4_242,
                nodeID: "COMMENT_\(nodeID)",
                isPending: isPending
            )
        ],
        nodeID: nodeID,
        reviewNodeID: "REVIEW_1"
    )
}
