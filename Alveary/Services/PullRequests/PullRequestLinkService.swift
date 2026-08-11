import Foundation
import SwiftData

/// What a link attempt did. `superseded` and `alreadyLinked` are deliberately distinct: the first
/// is a race the user never asked about, the second is a request for something already done.
enum PullRequestLinkOutcome: Equatable {
    case linked(LinkedPullRequest)
    /// The owner already carried this link before anything was fetched.
    case alreadyLinked(LinkedPullRequest)
    /// The owner vanished, or a concurrent link for the same pull request landed while the
    /// validating fetch was in flight.
    case superseded
}

enum PullRequestUnlinkOutcome: Equatable {
    case unlinked(LinkedPullRequest)
    /// The owner exists but carries no such link — the end state the caller wanted.
    case notLinked
    case ownerUnavailable
}

/// Durable pull-request linking for a thread or project.
///
/// `PullRequestLinksViewModel` is per-window and owns the linking *UI* — in-flight state, error
/// copy, the route to Git settings. The app-scoped half lives here so callers with no window,
/// namely the `alveary_host` thread tools, run exactly the same validation and persistence.
///
/// Validation and snapshotting are the same call by design: the `fetchDetail` that proves the pull
/// request exists is also what populates the stored summary, so a link can never hold a snapshot
/// of something unreachable.
@MainActor
final class PullRequestLinkService {
    private let modelContext: ModelContext
    private let service: any PullRequestsService
    private let now: () -> Date

    init(
        modelContext: ModelContext,
        service: any PullRequestsService,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.service = service
        self.now = now
    }

    /// Throws whatever `fetchDetail` or the save threw, unwrapped, so a caller can classify a
    /// `PullRequestsServiceError` (a missing or unauthenticated `gh`) on its own terms.
    ///
    /// `detail` lets a caller that just fetched this pull request hand its copy over instead of
    /// paying a second identical round trip. The invariant is that a stored link never holds a
    /// snapshot of something unreachable — not that this call is personally the fetcher — so a
    /// supplied detail is used only when it names the same pull request.
    func link(
        _ identifier: PullRequestIdentifier,
        owner: PullRequestLinkOwner,
        detail: PullRequestDetail? = nil
    ) async throws -> PullRequestLinkOutcome {
        guard let links = modelContext.linkedPullRequests(for: owner) else {
            return .superseded
        }
        if let existing = links.first(where: { $0.id == identifier }) {
            return .alreadyLinked(existing)
        }

        let resolvedDetail: PullRequestDetail
        if let detail, detail.id == identifier {
            resolvedDetail = detail
        } else {
            resolvedDetail = try await service.fetchDetail(identifier)
        }

        // Re-resolve after the fetch; the owner may be gone by now, or a concurrent link for the
        // same pull request may have landed meanwhile. A supplied detail may not have suspended
        // at all, but the check has to stay correct for both paths.
        guard let liveLinks = modelContext.linkedPullRequests(for: owner),
              !liveLinks.contains(where: { $0.id == identifier }) else {
            return .superseded
        }
        // One `now()` read feeds both timestamps so the summary's `updatedAt` fallback and
        // `linkedAt` cannot disagree, and tests keep one clock.
        let linkedAt = now()
        let link = LinkedPullRequest(
            summary: Self.makeSummary(from: resolvedDetail, linkedAt: linkedAt),
            linkedAt: linkedAt
        )
        modelContext.setLinkedPullRequests(liveLinks + [link], for: owner)
        try modelContext.save()
        return .linked(link)
    }

    /// Removes Alveary's local link only. Nothing here touches the pull request on GitHub.
    @discardableResult
    func unlink(
        _ identifier: PullRequestIdentifier,
        owner: PullRequestLinkOwner
    ) throws -> PullRequestUnlinkOutcome {
        guard var links = modelContext.linkedPullRequests(for: owner) else {
            return .ownerUnavailable
        }
        guard let removed = links.first(where: { $0.id == identifier }) else {
            return .notLinked
        }
        links.removeAll { $0.id == identifier }
        modelContext.setLinkedPullRequests(links, for: owner)
        try modelContext.save()
        return .unlinked(removed)
    }

    /// `PullRequestDetail` carries every field the pane falls back to `summary` for. The three
    /// that need a decision rather than a copy:
    /// - `updatedAt` is optional on the detail; the link time is the honest stand-in.
    /// - `isAuthored` gates the review footer's Approve / Request changes buttons until the live
    ///   detail lands, so an unknown viewer must read as not authored.
    /// - `isReviewRequested` / `hasReviewed` are involvement-search facts with no detail
    ///   equivalent, and nothing in the pane reads them.
    static func makeSummary(from detail: PullRequestDetail, linkedAt: Date = Date()) -> PullRequestSummary {
        PullRequestSummary(
            id: detail.id,
            title: detail.title,
            url: detail.url,
            status: detail.status,
            authorLogin: detail.authorLogin,
            authorAvatarURL: detail.authorAvatarURL,
            headRefName: detail.headRefName,
            baseRefName: detail.baseRefName,
            updatedAt: detail.updatedAt ?? linkedAt,
            additions: detail.additions,
            deletions: detail.deletions,
            isAuthored: detail.viewerLogin != nil && detail.viewerLogin == detail.authorLogin,
            isReviewRequested: false,
            hasReviewed: false
        )
    }
}
