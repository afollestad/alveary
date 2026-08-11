import Foundation
import XCTest

@testable import Alveary

/// The pure halves of `list_involved_prs`' paging: where a partly emitted page resumes from, and
/// the token that carries that position plus the search it belongs to.
final class PullRequestHostToolListCursorTests: XCTestCase {
    // MARK: - Advancing

    func testAdvancePastTheEmittedPrefixRatherThanThePageBoundary() {
        let summaries = (1...4).map { makePullRequestSummary(number: $0) }
        let emitted = Set(summaries.prefix(2).map(\.id))

        let outcome = PullRequestListCursorAdvance.outcome(
            pageInfo: PullRequestListPageInfo(
                endCursor: "c4",
                hasNextPage: true,
                rowCursors: ["c1", "c2", "c3", "c4"]
            ),
            summaries: summaries,
            incoming: nil,
            isConsumed: { emitted.contains($0.id) }
        )

        // `endCursor` would skip rows 3 and 4, which this response never showed.
        XCTAssertEqual(outcome, .resume(cursor: "c2"))
    }

    func testAConsumedRowNeedNotHaveBeenEmitted() {
        let summaries = (1...3).map { makePullRequestSummary(number: $0) }

        let outcome = PullRequestListCursorAdvance.outcome(
            pageInfo: PullRequestListPageInfo(endCursor: "c3", hasNextPage: true, rowCursors: ["c1", "c2", "c3"]),
            summaries: summaries,
            incoming: nil,
            // The first row was filtered out rather than shown; no later page can revive it.
            isConsumed: { $0.id.number < 2 }
        )

        XCTAssertEqual(outcome, .resume(cursor: "c1"))
    }

    func testAFullyEmittedPageAdvancesToItsBoundary() {
        let summaries = (1...2).map { makePullRequestSummary(number: $0) }

        let outcome = PullRequestListCursorAdvance.outcome(
            pageInfo: PullRequestListPageInfo(endCursor: "c2", hasNextPage: true, rowCursors: ["c1", "c2"]),
            summaries: summaries,
            incoming: nil,
            isConsumed: { _ in true }
        )

        XCTAssertEqual(outcome, .resume(cursor: "c2"))
    }

    func testAFullyEmittedLastPageIsExhausted() {
        let outcome = PullRequestListCursorAdvance.outcome(
            pageInfo: PullRequestListPageInfo(endCursor: "c1", hasNextPage: false, rowCursors: ["c1"]),
            summaries: [makePullRequestSummary(number: 1)],
            incoming: nil,
            isConsumed: { _ in true }
        )

        XCTAssertEqual(outcome, .exhausted)
    }

    func testAnEmptyPageIsExhausted() {
        let outcome = PullRequestListCursorAdvance.outcome(
            pageInfo: .exhausted,
            summaries: [],
            incoming: "c9",
            isConsumed: { _ in true }
        )

        XCTAssertEqual(outcome, .exhausted)
    }

    func testNothingConsumedKeepsWhereThePageWasFetchedFrom() {
        let summaries = [makePullRequestSummary(number: 1)]
        let pageInfo = PullRequestListPageInfo(endCursor: "c1", hasNextPage: true, rowCursors: ["c1"])

        // A bucket whose rows were all older than its siblings' contributes nothing to this page,
        // so its position must not move or those rows would never be shown.
        XCTAssertEqual(
            PullRequestListCursorAdvance.outcome(
                pageInfo: pageInfo,
                summaries: summaries,
                incoming: "c0",
                isConsumed: { _ in false }
            ),
            .resume(cursor: "c0")
        )
        XCTAssertEqual(
            PullRequestListCursorAdvance.outcome(
                pageInfo: pageInfo,
                summaries: summaries,
                incoming: nil,
                isConsumed: { _ in false }
            ),
            .restart
        )
    }

    // MARK: - Token

    func testTheTokenRoundTripsTheWholeQueryAndIsDeterministic() throws {
        let token = PullRequestListCursorToken(
            filter: .all,
            limit: 20,
            status: .merged,
            updatedAfter: Date(timeIntervalSince1970: 1_767_225_600),
            updatedBefore: Date(timeIntervalSince1970: 1_772_409_600),
            buckets: [.reviewRequested, .reviewed],
            cursors: [.reviewRequested: "requested-2"]
        )

        let encoded = try token.encoded()
        XCTAssertEqual(encoded, try token.encoded())
        // Base64url so the token survives a JSON argument untouched.
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))

        let decoded = try PullRequestListCursorToken.decoded(from: encoded, path: "arguments")
        XCTAssertEqual(decoded, token)
        // A bucket listed without a cursor restarts at its first page rather than being dropped.
        XCTAssertEqual(decoded.buckets, [.reviewRequested, .reviewed])
        XCTAssertNil(decoded.cursors[.reviewed])
    }

    func testGarbageAndNewerTokensAreRefusedWithARestartInstruction() throws {
        XCTAssertThrowsError(try PullRequestListCursorToken.decoded(from: "not-a-token", path: "arguments")) { error in
            XCTAssertTrue(error.localizedDescription.contains("omit cursor"), error.localizedDescription)
        }

        let newer = Data(#"{"v":99,"f":"all","l":50,"s":"open","bk":["authored"],"c":{}}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try PullRequestListCursorToken.decoded(from: newer, path: "arguments")) { error in
            XCTAssertTrue(error.localizedDescription.contains("newer version"), error.localizedDescription)
        }

        // Every minted token's limit was parser-capped, so one past the cap is forged or corrupt.
        let oversized = Data(#"{"v":1,"f":"all","l":500,"s":"open","bk":["authored"],"c":{}}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        XCTAssertThrowsError(try PullRequestListCursorToken.decoded(from: oversized, path: "arguments"))
    }
}
