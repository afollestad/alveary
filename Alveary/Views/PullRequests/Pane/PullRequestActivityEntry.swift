import Foundation

/// One row of the Overview conversation timeline: issue comments, review cards
/// (with their submitted threads nested), bare status events, and standalone
/// review threads merged chronologically.
struct PullRequestActivityEntry: Identifiable {
    enum Kind {
        case comment(PullRequestComment)
        case review(PullRequestReview)
        case statusEvent(PullRequestTimelineEvent)
        case thread(PullRequestReviewThread)
    }

    let id: Int
    let date: Date?
    let kind: Kind
    /// Threads submitted with this review, nested under its card like GitHub;
    /// non-empty only for `.review` entries.
    var nestedThreads: [PullRequestReviewThread] = []

    static func entries(from detail: PullRequestDetail) -> [PullRequestActivityEntry] {
        var merged: [MergedEntry] = detail.comments.map {
            MergedEntry(date: $0.createdAt, kind: .comment($0))
        }
        var threadsByReview: [String: [PullRequestReviewThread]] = [:]
        for thread in detail.reviewThreads {
            if let reviewNodeID = thread.reviewNodeID {
                threadsByReview[reviewNodeID, default: []].append(thread)
            }
        }
        // A body-less "commented" review with no threads here would be an empty
        // shell, so it hides — but one carrying threads renders as the group
        // header its threads nest under, like GitHub's "reviewed" row (inline-only
        // review submissions have no top-level comment at all).
        let visibleReviews = detail.reviews.filter { review in
            switch review.state {
            case .approved, .changesRequested, .dismissed:
                return true
            case .commented, .pending:
                return !PullRequestMarkdown.sanitized(review.bodyMarkdown).isEmpty
                    || !review.reactions.isEmpty
                    || review.nodeID.map { threadsByReview[$0]?.isEmpty == false } ?? false
            }
        }
        // Threads whose review is hidden or unknown fall back to standalone
        // timeline entries, keeping the fetched order so equal-date threads
        // render deterministically.
        let visibleReviewNodeIDs = Set(visibleReviews.compactMap(\.nodeID))
        let standaloneThreads = detail.reviewThreads.filter { thread in
            guard let reviewNodeID = thread.reviewNodeID else {
                return true
            }
            return !visibleReviewNodeIDs.contains(reviewNodeID)
        }
        merged.append(contentsOf: visibleReviews.map { review in
            MergedEntry(
                date: review.submittedAt,
                kind: .review(review),
                threads: review.nodeID.flatMap { threadsByReview[$0] } ?? []
            )
        })
        merged.append(contentsOf: Self.visibleTimelineEvents(detail.timelineEvents).map {
            MergedEntry(date: $0.createdAt, kind: .statusEvent($0))
        })
        // Standalone review threads interleave chronologically, dated by their
        // root comment.
        merged.append(contentsOf: standaloneThreads.map {
            MergedEntry(date: $0.comments.first?.createdAt, kind: .thread($0))
        })
        let sorted = merged.sorted { lhs, rhs in
            (lhs.date ?? .distantPast) < (rhs.date ?? .distantPast)
        }
        return sorted.enumerated().map { index, entry in
            PullRequestActivityEntry(id: index, date: entry.date, kind: entry.kind, nestedThreads: entry.threads)
        }
    }

    /// Merging a pull request emits a `closed` event alongside the `merged` one,
    /// which reads as a duplicate terminal row. Drop only closures at or after the
    /// merge, so a genuine close-then-reopen earlier in the history still shows.
    static func visibleTimelineEvents(
        _ events: [PullRequestTimelineEvent]
    ) -> [PullRequestTimelineEvent] {
        guard let mergedAt = events.first(where: { $0.kind == .merged })?.createdAt else {
            return events
        }
        return events.filter { event in
            guard event.kind == .closed, let closedAt = event.createdAt else {
                return true
            }
            return closedAt < mergedAt
        }
    }
}

/// Pre-sort accumulation shape for `entries(from:)`.
private struct MergedEntry {
    let date: Date?
    let kind: PullRequestActivityEntry.Kind
    var threads: [PullRequestReviewThread] = []
}
