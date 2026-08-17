import Foundation
import XCTest

@testable import Alveary

/// Relocation is deliberately conservative: it exists so a comment whose line moved still publishes,
/// and it must refuse rather than guess, because a wrong match posts review feedback onto unrelated
/// code with no way for the user to tell.
final class ReviewProposalAnchorResolutionTests: XCTestCase {
    func testAnUnmovedCommentIsLeftAlone() {
        let files = DiffParser.parse(Self.diff(lines: ["alpha()", "beta()", "gamma()"]))
        let comment = Self.comment(line: 2, content: "beta()")

        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve([comment], against: files),
            [.unchanged(line: 2)]
        )
    }

    /// The trap this whole type exists for: inserting a line above leaves the stored *number*
    /// occupied by different code, so a number-only check would publish the comment against it.
    func testALineNumberStillExistingIsNotEnoughToCountAsUnchanged() {
        let files = DiffParser.parse(
            Self.diff(lines: ["inserted()", "alpha()", "beta()", "gamma()"])
        )
        // Staged when `beta()` sat on line 2. Line 2 still exists — it holds `alpha()` now.
        let comment = Self.comment(line: 2, content: "beta()")

        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve([comment], against: files),
            [.relocated(from: 2, line: 3)]
        )
    }

    /// A fingerprint-less comment keeps the old number-only behaviour, because there is nothing
    /// else to go on — the alternative would make every pre-v3 envelope unconfirmable.
    func testAFingerprintlessCommentFallsBackToItsStoredNumber() {
        let files = DiffParser.parse(Self.diff(lines: ["alpha()", "beta()"]))
        let comment = Self.comment(line: 2, content: nil)

        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve([comment], against: files),
            [.unchanged(line: 2)]
        )
    }

    func testAMovedLineRelocatesToItsNewNumber() {
        let files = DiffParser.parse(
            Self.diff(lines: ["inserted()", "alpha()", "beta()", "gamma()"], startLine: 1)
        )
        // Staged when `gamma()` sat on line 3; a prepended line pushed it to 4.
        let comment = Self.comment(line: 3, content: "gamma()", context: ["alpha()", "beta()"])

        let resolution = ReviewProposalAnchorResolution.resolve([comment], against: files)

        XCTAssertEqual(resolution, [.relocated(from: 3, line: 4)])
        XCTAssertEqual(ReviewProposalAnchorResolution.resolvedLines([comment], against: files), [4])
    }

    /// Two lines reading the same thing, and no context to separate them, is exactly the case that
    /// must not be guessed.
    func testAnAmbiguousMatchIsStaleRatherThanAGuess() {
        let files = DiffParser.parse(
            Self.diff(lines: ["guard let x else { return }", "work()", "guard let x else { return }"])
        )
        let comment = Self.comment(line: 9, content: "guard let x else { return }")

        XCTAssertEqual(ReviewProposalAnchorResolution.resolve([comment], against: files), [.stale])
    }

    func testContextSeparatesTwoIdenticalLines() {
        let files = DiffParser.parse(
            Self.diff(lines: ["guard let x else { return }", "work()", "guard let x else { return }"])
        )
        // Only the second occurrence has `work()` above it and nothing below.
        let comment = Self.comment(
            line: 9,
            content: "guard let x else { return }",
            context: ["guard let x else { return }", "work()"]
        )

        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve([comment], against: files),
            [.relocated(from: 9, line: 3)]
        )
    }

    /// A v2 envelope, and any comment a person composed in the pane, carries no fingerprint.
    func testAcommentWithoutAFingerprintCannotRelocate() {
        let files = DiffParser.parse(Self.diff(lines: ["alpha()"]))
        let comment = Self.comment(line: 9, content: nil)

        XCTAssertEqual(ReviewProposalAnchorResolution.resolve([comment], against: files), [.stale])
    }

    func testAMatchOnTheOtherSideIsNotUsed() {
        let files = DiffParser.parse(
            """
            diff --git a/Sources/Alpha.swift b/Sources/Alpha.swift
            --- a/Sources/Alpha.swift
            +++ b/Sources/Alpha.swift
            @@ -1,1 +1,1 @@
            -alpha()
            +beta()
            """
        )
        // `alpha()` exists only as a deleted line, which anchors LEFT; a RIGHT comment cannot use it.
        let comment = Self.comment(line: 9, content: "alpha()")

        XCTAssertEqual(ReviewProposalAnchorResolution.resolve([comment], against: files), [.stale])
    }

    func testResolutionsComeBackInEnvelopeOrder() {
        let files = DiffParser.parse(Self.diff(lines: ["alpha()", "beta()"]))
        let comments = [
            Self.comment(line: 1, content: "alpha()"),
            Self.comment(line: 9, content: "nothing matches this"),
            Self.comment(line: 2, content: "beta()")
        ]

        // Order is what lets an index still address the comment a card's Remove would drop.
        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve(comments, against: files),
            [.unchanged(line: 1), .stale, .unchanged(line: 2)]
        )
    }

    func testAFingerprintCapturedFromADiffRelocatesAgainstIt() {
        let staged = DiffParser.parse(Self.diff(lines: ["alpha()", "beta()", "gamma()"]))
        let fingerprint = try? XCTUnwrap(
            ReviewProposalAnchorResolution.fingerprint(
                path: Self.path,
                line: 3,
                side: .right,
                in: staged
            )
        )
        let comment = Self.comment(
            line: 3,
            content: fingerprint?.content,
            context: fingerprint?.context
        )
        let moved = DiffParser.parse(
            Self.diff(lines: ["inserted()", "alpha()", "beta()", "gamma()"])
        )

        XCTAssertEqual(fingerprint?.content, "gamma()")
        XCTAssertEqual(
            ReviewProposalAnchorResolution.resolve([comment], against: moved),
            [.relocated(from: 3, line: 4)]
        )
    }

    private static let path = "Sources/Alpha.swift"

    private static func comment(
        line: Int,
        content: String?,
        context: [String]? = nil
    ) -> PullRequestReviewProposalRecord.Comment {
        PullRequestReviewProposalRecord.Comment(
            path: path,
            line: line,
            side: "RIGHT",
            body: "Body",
            anchorContent: content,
            anchorContext: context
        )
    }

    /// Added lines, so every one anchors RIGHT on its new-side number starting at `startLine`.
    private static func diff(lines: [String], startLine: Int = 1) -> String {
        let added = lines.map { "+\($0)" }.joined(separator: "\n")
        return """
            diff --git a/\(path) b/\(path)
            --- a/\(path)
            +++ b/\(path)
            @@ -0,0 +\(startLine),\(lines.count) @@
            \(added)
            """
    }
}
