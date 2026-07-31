import Foundation
import Observation
import SwiftData

/// Owns the pull-request links on threads and projects: parsing what the user
/// pastes, validating it against GitHub, and persisting the result on the
/// owning `AgentThread` or `Project` through `PullRequestLinkOwner`.
///
/// Separate from `PullRequestsViewModel`, which owns the browsing list and the
/// detail panes and holds no `ModelContext`. This one holds the context; it
/// hands a stored snapshot to `PullRequestsViewModel.requestDetails(_:)` to open
/// a pane rather than duplicating any pane state.
@MainActor
@Observable
final class PullRequestLinksViewModel {
    private let modelContext: ModelContext
    private let service: any PullRequestsService
    private let now: () -> Date

    /// The failed link attempt's message, cleared when the user edits the field
    /// or the popover closes.
    private(set) var linkErrorMessage: String?
    /// True while a validating fetch is in flight; disables the Link button.
    private(set) var isLinking = false
    /// Set when the failure is a missing or unauthenticated `gh`, so the popover
    /// can offer a route to Git settings instead of only stating the problem.
    private(set) var linkFailureNeedsGitSettings = false

    init(
        modelContext: ModelContext,
        service: any PullRequestsService,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.service = service
        self.now = now
    }

    func clearLinkError() {
        linkErrorMessage = nil
        linkFailureNeedsGitSettings = false
    }

    /// Validates and links what the user pasted. Validation and snapshotting are
    /// the same call: the `fetchDetail` that proves the pull request exists is
    /// also what populates the stored summary.
    func link(urlText: String, owner: PullRequestLinkOwner) async {
        guard !isLinking else {
            return
        }
        guard let identifier = PullRequestURLParser.identifier(from: urlText) else {
            clearLinkError()
            linkErrorMessage = "Enter a GitHub pull request URL, like https://github.com/owner/repo/pull/123."
            return
        }
        await link(identifier, owner: owner)
    }

    /// Links an already-parsed identifier — the tail of `link(urlText:owner:)`,
    /// and the create-pull-request flow's entry point, which has the identifier
    /// straight from `gh pr create` and needs no URL round trip.
    func link(_ identifier: PullRequestIdentifier, owner: PullRequestLinkOwner) async {
        guard !isLinking else {
            return
        }
        clearLinkError()

        guard let links = modelContext.linkedPullRequests(for: owner) else {
            return
        }
        guard !links.contains(where: { $0.id == identifier }) else {
            linkErrorMessage = "\(identifier.displayKey) is already linked."
            return
        }

        isLinking = true
        defer { isLinking = false }

        let detail: PullRequestDetail
        do {
            detail = try await service.fetchDetail(identifier)
        } catch {
            applyLinkFailure(error)
            return
        }

        // Re-resolve after the await; the owner may be gone by now, or a
        // concurrent link for the same pull request may have landed meanwhile.
        guard let liveLinks = modelContext.linkedPullRequests(for: owner),
              !liveLinks.contains(where: { $0.id == identifier }) else {
            return
        }
        // One `now()` read feeds both timestamps so the summary's `updatedAt`
        // fallback and `linkedAt` cannot disagree, and tests keep one clock.
        let linkedAt = now()
        let link = LinkedPullRequest(summary: Self.makeSummary(from: detail, linkedAt: linkedAt), linkedAt: linkedAt)
        modelContext.setLinkedPullRequests(liveLinks + [link], for: owner)
        save()
    }

    func unlink(_ identifier: PullRequestIdentifier, owner: PullRequestLinkOwner) {
        guard var links = modelContext.linkedPullRequests(for: owner) else {
            return
        }
        links.removeAll { $0.id == identifier }
        modelContext.setLinkedPullRequests(links, for: owner)
        save()
    }

    /// Writes a status the open pane already learned back into the stored
    /// snapshot, so the toolbar glyph follows a merge, close, reopen, or
    /// ready-for-review the moment it lands rather than at the next open.
    /// Idempotent: an unchanged status writes nothing.
    func applyStatus(
        _ status: PullRequestStatus,
        to identifier: PullRequestIdentifier,
        owner: PullRequestLinkOwner
    ) {
        guard var links = modelContext.linkedPullRequests(for: owner),
              let index = links.firstIndex(where: { $0.id == identifier }),
              links[index].summary.status != status else {
            return
        }
        links[index].summary.status = status
        modelContext.setLinkedPullRequests(links, for: owner)
        save()
    }

    /// Rewrites a link's stored snapshot from GitHub. Called when its pane opens
    /// so the toolbar glyph follows merges and closures without its own polling.
    func refreshSnapshot(_ identifier: PullRequestIdentifier, owner: PullRequestLinkOwner) async {
        guard let detail = try? await service.fetchDetail(identifier),
              var links = modelContext.linkedPullRequests(for: owner),
              let index = links.firstIndex(where: { $0.id == identifier }) else {
            return
        }
        links[index].summary = Self.makeSummary(from: detail)
        modelContext.setLinkedPullRequests(links, for: owner)
        save()
    }

    /// `PullRequestDetail` carries every field the pane falls back to `summary`
    /// for. The three that need a decision rather than a copy:
    /// - `updatedAt` is optional on the detail; the link time is the honest stand-in.
    /// - `isAuthored` gates the review footer's Approve / Request changes buttons
    ///   until the live detail lands, so an unknown viewer must read as not authored.
    /// - `isReviewRequested` / `hasReviewed` are involvement-search facts with no
    ///   detail equivalent, and nothing in the pane reads them.
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
            reviewDecision: detail.reviewDecision,
            isAuthored: detail.viewerLogin != nil && detail.viewerLogin == detail.authorLogin,
            isReviewRequested: false,
            hasReviewed: false
        )
    }

    private func applyLinkFailure(_ error: Error) {
        guard let serviceError = error as? PullRequestsServiceError else {
            linkErrorMessage = error.localizedDescription
            return
        }
        linkErrorMessage = serviceError.errorDescription ?? error.localizedDescription
        switch serviceError {
        case .ghNotInstalled, .notAuthenticated:
            linkFailureNeedsGitSettings = true
        case .rateLimited, .requestFailed, .responseTooLarge, .decodingFailed, .transport:
            linkFailureNeedsGitSettings = false
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            linkErrorMessage = error.localizedDescription
        }
    }
}
