#if DEBUG
import Foundation

/// Canned pull requests for `DemoPullRequestsService` and the seeder's links, so the Pull Requests
/// screen, the sidebar glyphs, and the transcript cards all name the same six.
///
/// This file holds the list-screen half. Each one's conversation lives in
/// `DemoPullRequestFixtures+Conversations.swift` and its diff in `+Diffs.swift`.
enum DemoPullRequestFixtures {
    /// The signed-in user: the author of every authored fixture, and the reviewer the rest
    /// request. Comment and review menus gate on it, so a fixture attributed to anyone else
    /// renders without one.
    static let viewerLogin = "rowan"

    static let onboardingWalkthrough = PullRequestIdentifier(owner: "demo", repo: "waypoint", number: 61)
    static let searchEmptyState = PullRequestIdentifier(owner: "demo", repo: "hummingbird", number: 74)
    static let webhookRetries = PullRequestIdentifier(owner: "demo", repo: "ledger", number: 128)
    static let tileCaching = PullRequestIdentifier(owner: "demo", repo: "waypoint", number: 57)
    static let rateLimitMiddleware = PullRequestIdentifier(owner: "demo", repo: "ledger", number: 96)
    static let filterBottomSheet = PullRequestIdentifier(owner: "demo", repo: "hummingbird", number: 41)

    static let summaries: [PullRequestSummary] = [
        makeSummary(
            id: onboardingWalkthrough,
            title: "Rework the onboarding walkthrough",
            author: viewerLogin,
            branch: "alveary/onboarding-walkthrough",
            status: .open,
            updatedAt: DemoData.minutesAgo(25),
            additions: 19,
            deletions: 6,
            isAuthored: true
        ),
        makeSummary(
            id: searchEmptyState,
            title: "Search results empty state",
            author: viewerLogin,
            branch: "alveary/search-empty-state",
            status: .open,
            updatedAt: DemoData.hoursAgo(4),
            additions: 14,
            deletions: 4,
            isAuthored: true
        ),
        makeSummary(
            id: webhookRetries,
            title: "Idempotent webhook retries",
            author: "marcus",
            branch: "webhook-retries",
            status: .open,
            updatedAt: DemoData.hoursAgo(9),
            additions: 38,
            deletions: 3,
            isReviewRequested: true
        ),
        makeSummary(
            id: tileCaching,
            title: "Cache tile downloads for offline maps",
            author: "priya",
            branch: "offline-tile-cache",
            status: .open,
            updatedAt: DemoData.daysAgo(1),
            additions: 19,
            deletions: 6,
            isReviewRequested: true
        ),
        makeSummary(
            id: rateLimitMiddleware,
            title: "Rate limit middleware for the public API",
            author: viewerLogin,
            branch: "alveary/rate-limit-middleware",
            status: .merged,
            updatedAt: DemoData.daysAgo(6),
            additions: 9,
            deletions: 3,
            isAuthored: true
        ),
        makeSummary(
            id: filterBottomSheet,
            title: "Try a bottom sheet for filters",
            author: "ines",
            branch: "filter-bottom-sheet",
            status: .closed,
            updatedAt: DemoData.daysAgo(33),
            additions: 3,
            deletions: 14,
            hasReviewed: true
        )
    ]

    static func summary(for id: PullRequestIdentifier) -> PullRequestSummary? {
        summaries.first { $0.id == id }
    }

    // `PullRequestSummary` has fifteen stored properties and only its synthesized memberwise
    // init, so this keeps the six call sites above readable and inside the type-check budget.
    // swiftlint:disable:next function_parameter_count
    private static func makeSummary(
        id: PullRequestIdentifier,
        title: String,
        author: String,
        branch: String,
        status: PullRequestStatus,
        updatedAt: Date,
        additions: Int,
        deletions: Int,
        isAuthored: Bool = false,
        isReviewRequested: Bool = false,
        hasReviewed: Bool = false
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: id,
            title: title,
            url: URL(string: "https://github.com/\(id.nameWithOwner)/pull/\(id.number)"),
            status: status,
            authorLogin: author,
            // Nil so rows render the deterministic letter avatar instead of fetching one.
            authorAvatarURL: nil,
            headRefName: branch,
            baseRefName: "main",
            updatedAt: updatedAt,
            additions: additions,
            deletions: deletions,
            isAuthored: isAuthored,
            isReviewRequested: isReviewRequested,
            hasReviewed: hasReviewed
        )
    }
}
#endif
