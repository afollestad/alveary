import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// The strict argument reading the service tests do not reach individually: every refusal here
/// is what stands between an unadvertised or malformed field and a GitHub write.
@MainActor
final class PullRequestHostToolRequestParserTests: XCTestCase {
    private let parser = PullRequestHostToolRequestParser()
    private static let url = "https://github.com/octo/alpha/pull/7"

    func testUnknownKeysAreRefusedNotIgnored() {
        XCTAssertThrowsError(
            try parser.parseListRequest(arguments: ["filter": .string("all"), "repo": .string("octo/alpha")])
        ) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("repo"))
        }
    }

    func testAnInvalidFilterNamesTheValidValues() {
        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["filter": .string("mine")])) { error in
            XCTAssertTrue(error.localizedDescription.contains("all, authored, reviewing, reviewed"))
        }
    }

    /// The two review scopes are separate searches, so each has to reach the service as one bucket:
    /// `reviewing` is what awaits the user's review and `reviewed` is what already had it.
    func testTheReviewFiltersEachResolveToOneBucket() throws {
        XCTAssertEqual(
            try parser.parseListRequest(arguments: ["filter": .string("reviewing")]).buckets,
            [.reviewRequested]
        )
        XCTAssertEqual(
            try parser.parseListRequest(arguments: ["filter": .string("reviewed")]).buckets,
            [.reviewed]
        )
    }

    /// The no-arguments call is what every model makes first, so its defaults are the behavior
    /// contract: everything the user is involved in, open only, the newest fifty.
    func testAnEmptyListCallKeepsTheDefaultsItAlwaysHad() throws {
        let request = try parser.parseListRequest(arguments: [:])

        XCTAssertEqual(request.filter, .all)
        XCTAssertEqual(request.status, .open)
        XCTAssertEqual(request.limit, PullRequestHostToolLimits.maxListRows)
        XCTAssertNil(request.updatedAfter)
        XCTAssertNil(request.updatedBefore)
        XCTAssertEqual(request.buckets, Set(PullRequestInvolvementBucket.allCases))
        XCTAssertTrue(request.cursors.isEmpty)
    }

    func testListOptionsAreReadAndBounded() throws {
        let request = try parser.parseListRequest(arguments: [
            "filter": .string("authored"),
            "status": .string("merged"),
            "limit": .number(10),
            "updated_after": .string("2026-01-01"),
            "updated_before": .string("2026-03-02")
        ])

        XCTAssertEqual(request.filter, .authored)
        XCTAssertEqual(request.status, .merged)
        XCTAssertEqual(request.limit, 10)
        XCTAssertEqual(request.updatedAfter, Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(request.updatedBefore, Date(timeIntervalSince1970: 1_772_409_600))
        XCTAssertEqual(request.buckets, [.authored])

        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["limit": .number(0)]))
        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["limit": .number(51)]))
        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["status": .string("all")]))
        // A lenient parse would search a window the user never named and report it as theirs.
        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["updated_after": .string("2026-1-1")]))
        XCTAssertThrowsError(try parser.parseListRequest(arguments: [
            "updated_after": .string("2026-03-02"),
            "updated_before": .string("2026-01-01")
        ]))
    }

    /// A paginating model passes the cursor alone, so the token has to supply the rest of the
    /// query — otherwise page two would silently be a different search.
    func testACursorAloneInheritsTheQueryItIsPaging() throws {
        // `all` is the only multi-bucket filter, so it is what can carry a token down to one
        // bucket; the non-default status, limit, and bound are what prove the token supplied the
        // query rather than the parser falling back to its defaults.
        let token = PullRequestListCursorToken(
            filter: .all,
            limit: 5,
            status: .closed,
            updatedAfter: Date(timeIntervalSince1970: 1_767_225_600),
            updatedBefore: nil,
            buckets: [.reviewed],
            cursors: [.reviewed: "reviewed-5"]
        )

        let request = try parser.parseListRequest(arguments: ["cursor": .string(try token.encoded())])

        XCTAssertEqual(request.filter, .all)
        XCTAssertEqual(request.limit, 5)
        XCTAssertEqual(request.status, .closed)
        XCTAssertEqual(request.updatedAfter, Date(timeIntervalSince1970: 1_767_225_600))
        // Only the buckets with pages left, so a drained one costs no GitHub search.
        XCTAssertEqual(request.buckets, [.reviewed])
        XCTAssertEqual(request.cursors, [.reviewed: "reviewed-5"])
    }

    func testAnArgumentBesideACursorMayAgreeButNotContradict() throws {
        let token = PullRequestListCursorToken(
            filter: .authored,
            limit: 50,
            status: .open,
            updatedAfter: nil,
            updatedBefore: nil,
            buckets: [.authored],
            cursors: [:]
        )
        let cursor = try token.encoded()

        let agreeing = try parser.parseListRequest(arguments: [
            "cursor": .string(cursor),
            "filter": .string("authored")
        ])
        XCTAssertEqual(agreeing.filter, .authored)

        XCTAssertThrowsError(
            try parser.parseListRequest(arguments: ["cursor": .string(cursor), "filter": .string("reviewing")])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("disagrees"), error.localizedDescription)
        }
        XCTAssertThrowsError(
            try parser.parseListRequest(arguments: ["cursor": .string(cursor), "status": .string("merged")])
        )
    }

    func testAnUnreadableCursorIsRefusedRatherThanIgnored() {
        XCTAssertThrowsError(try parser.parseListRequest(arguments: ["cursor": .string("%%%")])) { error in
            XCTAssertTrue(error.localizedDescription.contains("cursor"), error.localizedDescription)
        }
    }

    func testAMalformedURLIsRefusedWithTheExpectedShapes() {
        XCTAssertThrowsError(try parser.parseIdentifier(arguments: ["url": .string("octo/alpha")])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                PullRequestHostToolServiceError.invalidPullRequestURL("octo/alpha").localizedDescription
            )
        }
    }

    func testTimelineLimitBoundsAreEnforced() throws {
        XCTAssertThrowsError(
            try parser.parseTimeline(arguments: ["url": .string(Self.url), "limit": .number(0)])
        )
        XCTAssertThrowsError(
            try parser.parseTimeline(arguments: ["url": .string(Self.url), "limit": .number(101)])
        )
        let defaulted = try parser.parseTimeline(arguments: ["url": .string(Self.url)])
        XCTAssertEqual(defaulted.limit, PullRequestHostToolLimits.defaultTimelineLimit)
    }

    func testDiffOffsetAndPathsShapeIsValidated() throws {
        XCTAssertThrowsError(
            try parser.parseDiff(arguments: ["url": .string(Self.url), "offset": .number(-1)])
        )
        XCTAssertThrowsError(
            try parser.parseDiff(arguments: ["url": .string(Self.url), "paths": .array([])])
        )
        XCTAssertThrowsError(
            try parser.parseDiff(
                arguments: [
                    "url": .string(Self.url),
                    "paths": .array([.string("a.swift"), .string("a.swift")])
                ]
            )
        )
        let parsed = try parser.parseDiff(arguments: ["url": .string(Self.url)])
        XCTAssertEqual(parsed.offset, 0)
        XCTAssertNil(parsed.paths)
    }

    func testReviewCommentSideDefaultsRightAndRefusesUnknownValues() throws {
        var comment: [String: AgentCLIKit.JSONValue] = [
            "path": .string("Sources/A.swift"),
            "line": .number(3),
            "body": .string("Guard this.")
        ]
        XCTAssertEqual(try parser.parseReviewProposal(arguments: Self.batch([comment])).comments.first?.side, .right)

        comment["side"] = .string("BOTH")
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: Self.batch([comment])))
    }

    func testAReviewCommentBatchIsBoundedAtBothEnds() throws {
        // Omitting the array is the summary-only shape; passing it empty is a refusal, so the
        // two spellings cannot silently mean the same call.
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: Self.batch([]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("omit it"), error.localizedDescription)
        }
        let summaryOnly = try parser.parseReviewProposal(
            arguments: ["url": .string(Self.url), "event": .string("approve")]
        )
        XCTAssertTrue(summaryOnly.comments.isEmpty)
        let overCap = (0...PullRequestHostToolLimits.maxReviewCommentsPerProposal).map { index in
            Self.comment(line: index + 1)
        }
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: Self.batch(overCap))) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("\(PullRequestHostToolLimits.maxReviewCommentsPerProposal)"),
                error.localizedDescription
            )
        }
        // Two remarks on one line are legal GitHub state, so a duplicate anchor is not the
        // parser's to refuse.
        let duplicated = try parser.parseReviewProposal(arguments: Self.batch([Self.comment(), Self.comment()]))
        XCTAssertEqual(duplicated.comments.count, 2)
    }

    func testAMalformedCommentIsRefusedByItsIndex() throws {
        XCTAssertThrowsError(
            try parser.parseReviewProposal(
                arguments: [
                    "url": .string(Self.url),
                    "event": .string("comment"),
                    "comments": .array([.string("x")])
                ]
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("comments[0]"), error.localizedDescription)
        }
        var unknownKey = Self.comment()
        unknownKey["file"] = .string("Sources/A.swift")
        let withUnknownKey = Self.batch([Self.comment(), unknownKey])
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: withUnknownKey)) { error in
            XCTAssertTrue(error.localizedDescription.contains("comments[1]"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("file"), error.localizedDescription)
        }
        var blankBody = Self.comment()
        blankBody["body"] = .string("   ")
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: Self.batch([blankBody])))
        var zeroLine = Self.comment()
        zeroLine["line"] = .number(0)
        XCTAssertThrowsError(try parser.parseReviewProposal(arguments: Self.batch([zeroLine])))
    }

    func testAnUnknownReviewEventNamesTheValidOnes() {
        XCTAssertThrowsError(
            try parser.parseReviewProposal(
                arguments: ["url": .string(Self.url), "event": .string("merge")]
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("approve, request_changes, comment"))
        }
    }

    /// Models emit `""` for an optional field they have nothing to say for, and the two spellings
    /// mean the same call — so the blank one may not be refused, nor hash differently.
    func testABlankOptionalFieldReadsAsAnOmittedOne() throws {
        let blank = try parser.parseReviewProposal(
            arguments: ["url": .string(Self.url), "event": .string("comment"), "body": .string("")]
        )
        XCTAssertNil(blank.body)

        let omitted = try parser.parseReviewProposal(
            arguments: ["url": .string(Self.url), "event": .string("comment")]
        )
        XCTAssertEqual(blank.canonicalPayloadHash, omitted.canonicalPayloadHash)

        // Only emptiness is forgiven; a value of the wrong type is still a refusal.
        XCTAssertThrowsError(
            try parser.parseReviewProposal(
                arguments: ["url": .string(Self.url), "event": .string("comment"), "body": .number(1)]
            )
        )
    }

    /// The retry hash must distinguish requests that differ in any field the mutation uses, and
    /// must include the tool name so two tools cannot replay each other's receipts.
    func testCanonicalHashesDifferByFieldAndTool() throws {
        let comment = try parser.parseComment(
            arguments: ["url": .string(Self.url), "body": .string("Same text")]
        )
        let differentBody = try parser.parseComment(
            arguments: ["url": .string(Self.url), "body": .string("Other text")]
        )
        XCTAssertNotEqual(comment.canonicalPayloadHash, differentBody.canonicalPayloadHash)

        let reply = try parser.parseThreadReply(
            arguments: [
                "url": .string(Self.url),
                "thread_id": .string("T1"),
                "body": .string("Same text")
            ]
        )
        XCTAssertNotEqual(comment.canonicalPayloadHash, reply.canonicalPayloadHash)
    }

    /// The staged comments are confirmed and written in order, so which review the user saw
    /// depends on it: a reordered call is a different call, not a retry of the first.
    func testABatchHashCoversEveryCommentAndTheirOrder() throws {
        let first = Self.comment(line: 1, body: "First")
        let second = Self.comment(line: 2, body: "Second")
        let ordered = try parser.parseReviewProposal(arguments: Self.batch([first, second]))
        let reordered = try parser.parseReviewProposal(arguments: Self.batch([second, first]))
        XCTAssertNotEqual(ordered.canonicalPayloadHash, reordered.canonicalPayloadHash)

        let summaryOnly = try parser.parseReviewProposal(
            arguments: ["url": .string(Self.url), "event": .string("comment")]
        )
        XCTAssertNotEqual(ordered.canonicalPayloadHash, summaryOnly.canonicalPayloadHash)

        let edited = try parser.parseReviewProposal(
            arguments: Self.batch([first, Self.comment(line: 2, body: "Rewritten")])
        )
        XCTAssertNotEqual(ordered.canonicalPayloadHash, edited.canonicalPayloadHash)

        // Side is hashed after defaulting, so naming the default is the same call as omitting it.
        var explicitSide = first
        explicitSide["side"] = .string(PullRequestDiffSide.right.rawValue)
        let defaulted = try parser.parseReviewProposal(arguments: Self.batch([first]))
        let explicit = try parser.parseReviewProposal(arguments: Self.batch([explicitSide]))
        XCTAssertEqual(defaulted.canonicalPayloadHash, explicit.canonicalPayloadHash)
    }

    private static func comment(
        path: String = "Sources/A.swift",
        line: Int = 3,
        body: String = "Guard this."
    ) -> [String: AgentCLIKit.JSONValue] {
        ["path": .string(path), "line": .number(Double(line)), "body": .string(body)]
    }

    private static func batch(
        _ comments: [[String: AgentCLIKit.JSONValue]]
    ) -> [String: AgentCLIKit.JSONValue] {
        [
            "url": .string(url),
            "event": .string("comment"),
            "comments": .array(comments.map(AgentCLIKit.JSONValue.object))
        ]
    }
}
