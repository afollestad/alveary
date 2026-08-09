#if DEBUG
import Foundation
import XCTest

@testable import Alveary

/// Guards the invariants the fake pull-request conversations have to hold to render: every summary
/// resolves to a detail, every timeline row is orderable, and every review-thread anchor names a
/// line the served diff actually draws. All three fail silently in the UI.
final class DemoPullRequestFixturesTests: XCTestCase {
    func testEverySummaryResolvesToADetailAndADiff() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let detail = try XCTUnwrap(DemoPullRequestFixtures.detail(for: summary.id), summary.id.displayKey)
            XCTAssertEqual(detail.title, summary.title)
            XCTAssertEqual(detail.status, summary.status)
            XCTAssertNotNil(DemoPullRequestFixtures.diff(for: summary.id), summary.id.displayKey)

            let createdAt = try XCTUnwrap(detail.createdAt, summary.id.displayKey)
            XCTAssertLessThan(createdAt, summary.updatedAt, summary.id.displayKey)
            XCTAssertFalse(detail.bodyMarkdown.isEmpty, summary.id.displayKey)
            XCTAssertEqual(detail.viewerLogin, DemoPullRequestFixtures.viewerLogin)
        }
    }

    func testEveryDetailRendersANonEmptyTimelineWithDistinctDates() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let detail = try XCTUnwrap(DemoPullRequestFixtures.detail(for: summary.id))
            let entries = PullRequestActivityEntry.entries(from: detail)
            XCTAssertFalse(entries.isEmpty, "\(summary.id.displayKey) would render an empty timeline")

            // `entries(from:)` sorts on date and `Array.sorted` is not stable, so equal timestamps
            // would let two rows swap places between renders.
            let dates = entries.compactMap(\.date)
            XCTAssertEqual(dates.count, entries.count, "\(summary.id.displayKey) has an undated row")
            XCTAssertEqual(Set(dates).count, dates.count, "\(summary.id.displayKey) has rows sharing a timestamp")
        }
    }

    func testNestedThreadsNameAReviewThatExists() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let detail = try XCTUnwrap(DemoPullRequestFixtures.detail(for: summary.id))
            let reviewNodeIDs = Set(detail.reviews.compactMap(\.nodeID))
            for thread in detail.reviewThreads {
                guard let reviewNodeID = thread.reviewNodeID else {
                    continue
                }
                XCTAssertTrue(
                    reviewNodeIDs.contains(reviewNodeID),
                    "\(summary.id.displayKey) nests \(thread.path) under a review that is not in the detail"
                )
            }
        }
    }

    func testReviewThreadAnchorsResolveInTheServedDiff() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let detail = try XCTUnwrap(DemoPullRequestFixtures.detail(for: summary.id))
            let lines = try renderedLines(for: summary.id)
            // Outdated threads are excluded by design: the Changes tab cannot place an anchor a
            // force-push moved, so it never feeds them to the diff.
            for thread in detail.reviewThreads where !thread.isOutdated {
                let line = try XCTUnwrap(thread.line, thread.path)
                XCTAssertTrue(
                    lines.contains(RenderedLine(path: thread.path, line: line)),
                    "\(summary.id.displayKey) anchors a thread to \(thread.path):\(line), which its diff does not draw"
                )
            }
        }
    }

    func testSummaryDiffStatsMatchTheServedDiff() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let files = DiffParser.parse(try XCTUnwrap(DemoPullRequestFixtures.diff(for: summary.id)))
            // The pane header renders the summary's numbers above the Changes tab's hunks, so a
            // mismatch shows as one screenshot contradicting itself.
            XCTAssertEqual(summary.additions, files.reduce(0) { $0 + $1.linesAdded }, summary.id.displayKey)
            XCTAssertEqual(summary.deletions, files.reduce(0) { $0 + $1.linesDeleted }, summary.id.displayKey)

            let detail = try XCTUnwrap(DemoPullRequestFixtures.detail(for: summary.id))
            XCTAssertEqual(detail.changedFiles, files.count, summary.id.displayKey)
        }
    }

    func testHunkHeaderCountsMatchTheirBodies() throws {
        for summary in DemoPullRequestFixtures.summaries {
            let diff = try XCTUnwrap(DemoPullRequestFixtures.diff(for: summary.id))
            for file in DiffParser.parse(diff) {
                for hunk in file.hunks {
                    let old = hunk.lines.count { $0.type == .deleted || $0.type == .context }
                    let new = hunk.lines.count { $0.type == .added || $0.type == .context }
                    XCTAssertEqual(hunk.oldCount, old, "\(file.path) @@ -\(hunk.oldStart)")
                    XCTAssertEqual(hunk.newCount, new, "\(file.path) @@ +\(hunk.newStart)")
                }
            }
        }
    }

    func testProposalStagedCommentAnchorsResolveInTheServedDiff() throws {
        for proposal in [DemoReviewProposal.waypointTileCaching, .ledgerWebhookRetries] {
            let lines = try renderedLines(for: proposal.pullRequest)
            let staged = try stagedComments(in: proposal)
            XCTAssertEqual(staged.count, proposal.commentCount, proposal.threadName)
            for comment in staged {
                XCTAssertTrue(
                    lines.contains(RenderedLine(path: comment.path, line: comment.line)),
                    "\(proposal.threadName) stages a comment on \(comment.path):\(comment.line), which its diff does not draw"
                )
            }
        }
    }

    // MARK: Helpers

    /// Every `path`/`line` pair the pull request's diff renders on the new side — the only anchors
    /// the Changes tab can place a comment row on.
    private func renderedLines(for id: PullRequestIdentifier) throws -> Set<RenderedLine> {
        let diff = try XCTUnwrap(DemoPullRequestFixtures.diff(for: id), id.displayKey)
        var lines = Set<RenderedLine>()
        for file in DiffParser.parse(diff) {
            for hunk in file.hunks {
                for diffLine in hunk.lines {
                    guard let number = diffLine.newLineNumber else {
                        continue
                    }
                    lines.insert(RenderedLine(path: file.path, line: number))
                }
            }
        }
        // A diff that stopped parsing — an empty line inside a hunk ends it — would leave every
        // anchor assertion below vacuously true.
        XCTAssertFalse(lines.isEmpty, "\(id.displayKey) parses to no rendered lines")
        return lines
    }

    private func stagedComments(in proposal: DemoReviewProposal) throws -> [StagedComment] {
        let data = try XCTUnwrap(proposal.comments.data(using: .utf8))
        return try JSONDecoder().decode([StagedComment].self, from: data)
    }

    private struct RenderedLine: Hashable {
        let path: String
        let line: Int
    }

    private struct StagedComment: Decodable {
        let path: String
        let line: Int
    }
}
#endif
