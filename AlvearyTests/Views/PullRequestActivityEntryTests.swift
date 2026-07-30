import XCTest

@testable import Alveary

/// Overview-timeline entry building: review threads nest under the review card
/// they were submitted with, GitHub-style, and fall back to standalone entries
/// when their review is hidden or unknown.
@MainActor
final class PullRequestActivityEntryTests: XCTestCase {
    private static let id = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    private static func thread(reviewNodeID: String?, createdAt: Date? = nil) -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: "Sources/Parser.swift",
            line: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: "carol",
                    authorAvatarURL: nil,
                    bodyMarkdown: "Thread body",
                    createdAt: createdAt
                )
            ],
            nodeID: "PRT_1",
            reviewNodeID: reviewNodeID
        )
    }

    private static func review(
        state: PullRequestReviewState = .commented,
        body: String = "Review body",
        nodeID: String = "PRR_1"
    ) -> PullRequestReview {
        PullRequestReview(
            authorLogin: "carol",
            authorAvatarURL: nil,
            state: state,
            bodyMarkdown: body,
            submittedAt: Date(timeIntervalSince1970: 2_000),
            nodeID: nodeID
        )
    }

    func testThreadNestsUnderItsVisibleReview() {
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review()],
            reviewThreads: [Self.thread(reviewNodeID: "PRR_1")]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 1)
        guard case .review(let review) = entries[0].kind else {
            return XCTFail("Expected the review entry.")
        }
        XCTAssertEqual(review.nodeID, "PRR_1")
        XCTAssertEqual(entries[0].nestedThreads.map(\.nodeID), ["PRT_1"])
    }

    func testCarrierReviewWithThreadsRendersAsGroupHeader() {
        // An inline-only review submission has no top-level comment; its
        // body-less "commented" review still renders as the header its threads
        // nest under, like GitHub's "reviewed" row.
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review(body: "")],
            reviewThreads: [Self.thread(reviewNodeID: "PRR_1")]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 1)
        guard case .review(let review) = entries[0].kind else {
            return XCTFail("Expected the carrier review's group entry.")
        }
        XCTAssertEqual(review.nodeID, "PRR_1")
        XCTAssertEqual(entries[0].nestedThreads.map(\.nodeID), ["PRT_1"])
    }

    func testCarrierReviewWithoutThreadsStaysHidden() {
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review(body: "")]
        )

        XCTAssertTrue(PullRequestActivityEntry.entries(from: detail).isEmpty)
    }

    func testThreadOfUnknownReviewStaysStandalone() {
        // The thread references a review the detail does not carry (for example
        // beyond the query's first-50 window); it falls back to a flat entry.
        let detail = makePullRequestDetail(
            id: Self.id,
            reviewThreads: [Self.thread(reviewNodeID: "PRR_MISSING")]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 1)
        guard case .thread(let thread) = entries[0].kind else {
            return XCTFail("Expected the standalone thread entry.")
        }
        XCTAssertEqual(thread.nodeID, "PRT_1")
        XCTAssertTrue(entries[0].nestedThreads.isEmpty)
    }

    func testSiblingThreadsFromOneSubmissionShareOneGroup() {
        // Two inline comments from one review submission: both nest under the
        // same header, each as its own thread, in fetched order.
        let second = PullRequestReviewThread(
            path: "Sources/Other.swift",
            line: 4,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: "carol",
                    authorAvatarURL: nil,
                    bodyMarkdown: "Second thread",
                    createdAt: nil
                )
            ],
            nodeID: "PRT_2",
            reviewNodeID: "PRR_1"
        )
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review(body: "")],
            reviewThreads: [Self.thread(reviewNodeID: "PRR_1"), second]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].nestedThreads.map(\.nodeID), ["PRT_1", "PRT_2"])
    }

    func testThreadWithoutReviewAssociationStaysStandalone() {
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review()],
            reviewThreads: [Self.thread(reviewNodeID: nil, createdAt: Date(timeIntervalSince1970: 3_000))]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 2)
        guard case .review = entries[0].kind, case .thread = entries[1].kind else {
            return XCTFail("Expected the review, then the standalone thread.")
        }
        XCTAssertTrue(entries[0].nestedThreads.isEmpty)
    }

    func testNestedThreadDatesByItsReviewNotItsRootComment() {
        // The thread's root comment predates the review's submission timestamp;
        // nesting means the group sorts by the review, not the comment.
        let detail = makePullRequestDetail(
            id: Self.id,
            comments: [
                PullRequestComment(
                    authorLogin: "alice",
                    authorAvatarURL: nil,
                    bodyMarkdown: "In between",
                    createdAt: Date(timeIntervalSince1970: 1_500)
                )
            ],
            reviews: [Self.review()],
            reviewThreads: [Self.thread(reviewNodeID: "PRR_1", createdAt: Date(timeIntervalSince1970: 1_000))]
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 2)
        guard case .comment = entries[0].kind, case .review = entries[1].kind else {
            return XCTFail("Expected the comment first, then the review group.")
        }
        XCTAssertEqual(entries[1].nestedThreads.map(\.nodeID), ["PRT_1"])
    }

    private static func event(_ kind: PullRequestTimelineEvent.Kind, at seconds: TimeInterval) -> PullRequestTimelineEvent {
        PullRequestTimelineEvent(
            kind: kind,
            actorLogin: "afollestad",
            actorAvatarURL: nil,
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    /// GitHub emits a `closed` event alongside `merged`; the duplicate terminal
    /// row is dropped.
    func testMergeHidesItsAccompanyingCloseEvent() {
        let events = [
            Self.event(.merged, at: 2_000),
            Self.event(.closed, at: 2_000)
        ]

        let visible = PullRequestActivityEntry.visibleTimelineEvents(events)

        XCTAssertEqual(visible.map(\.kind), [.merged])
    }

    /// A genuine close before the merge (closed, reopened, then merged) is history
    /// the timeline must keep.
    func testCloseBeforeTheMergeIsKept() {
        let events = [
            Self.event(.closed, at: 1_000),
            Self.event(.reopened, at: 1_500),
            Self.event(.merged, at: 2_000),
            Self.event(.closed, at: 2_000)
        ]

        let visible = PullRequestActivityEntry.visibleTimelineEvents(events)

        XCTAssertEqual(visible.map(\.kind), [.closed, .reopened, .merged])
        XCTAssertEqual(visible.first?.createdAt, Date(timeIntervalSince1970: 1_000))
    }

    func testCloseWithoutAMergeIsKept() {
        let events = [Self.event(.closed, at: 1_000)]

        let visible = PullRequestActivityEntry.visibleTimelineEvents(events)

        XCTAssertEqual(visible.map(\.kind), [.closed])
    }
}

// MARK: - Pending review threads

extension PullRequestActivityEntryTests {
    private static func pendingThread() -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: "Sources/Parser.swift",
            line: 12,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: [
                PullRequestComment(
                    authorLogin: "viewer",
                    authorAvatarURL: nil,
                    bodyMarkdown: "Not submitted yet",
                    createdAt: Date(timeIntervalSince1970: 3_000),
                    nodeID: "PRRC_pending",
                    isPending: true
                )
            ],
            nodeID: "PRT_pending",
            reviewNodeID: "PRR_pending"
        )
    }

    /// The viewer's own draft is dropped from `reviews` at the mapping layer, so
    /// its thread has no visible carrier and lands as a standalone entry — which
    /// is what puts the orange "Pending" pill on the Overview timeline.
    func testPendingThreadRendersAsAStandaloneEntry() {
        let detail = makePullRequestDetail(
            id: Self.id,
            reviewThreads: [Self.pendingThread()],
            pendingReviewNodeID: "PRR_pending"
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 1)
        guard case .thread(let thread) = entries[0].kind else {
            return XCTFail("Expected a standalone thread entry.")
        }
        XCTAssertTrue(thread.isPending)
        // Dated by its root comment, like any other standalone thread.
        XCTAssertEqual(entries[0].date, Date(timeIntervalSince1970: 3_000))
    }

    func testPendingThreadDoesNotSuppressSubmittedActivity() {
        let detail = makePullRequestDetail(
            id: Self.id,
            reviews: [Self.review()],
            reviewThreads: [Self.thread(reviewNodeID: "PRR_1"), Self.pendingThread()],
            pendingReviewNodeID: "PRR_pending"
        )

        let entries = PullRequestActivityEntry.entries(from: detail)

        XCTAssertEqual(entries.count, 2)
        // The submitted review still nests its own thread.
        guard case .review = entries[0].kind else {
            return XCTFail("Expected the submitted review first.")
        }
        XCTAssertEqual(entries[0].nestedThreads.count, 1)
        guard case .thread(let pending) = entries[1].kind else {
            return XCTFail("Expected the pending thread second.")
        }
        XCTAssertTrue(pending.isPending)
    }
}
