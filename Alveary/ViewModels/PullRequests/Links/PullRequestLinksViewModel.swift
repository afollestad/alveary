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
    // Internal rather than private so `+DetectedLinks.swift` can reuse them.
    let modelContext: ModelContext
    let service: any PullRequestsService
    let now: () -> Date

    /// Detected links currently being fetched, so a repeated prompt tap or a
    /// duplicate detection cannot start a second identical fetch.
    @ObservationIgnored var linkingDetectedIdentifiers: Set<PullRequestIdentifier> = []

    /// The failed link attempt's message, cleared when the user edits the field
    /// or the popover closes.
    private(set) var linkErrorMessage: String?
    /// True while a validating fetch is in flight; disables the Link button.
    private(set) var isLinking = false
    /// Set when the failure is a missing or unauthenticated `gh`, so the popover
    /// can offer a route to Git settings instead of only stating the problem.
    private(set) var linkFailureNeedsGitSettings = false

    /// The durable half. This view model is per-window; the app-scoped `alveary_host` thread tools
    /// link through the same service, so validation and persistence cannot fork.
    private let linkService: PullRequestLinkService

    init(
        modelContext: ModelContext,
        service: any PullRequestsService,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.service = service
        self.now = now
        linkService = PullRequestLinkService(modelContext: modelContext, service: service, now: now)
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

        isLinking = true
        defer { isLinking = false }

        do {
            // A race the user never asked about stays silent; asking for a link that already
            // exists is worth saying out loud.
            if case .alreadyLinked = try await linkService.link(identifier, owner: owner) {
                linkErrorMessage = "\(identifier.displayKey) is already linked."
            }
        } catch {
            applyLinkFailure(error)
        }
    }

    func unlink(_ identifier: PullRequestIdentifier, owner: PullRequestLinkOwner) {
        do {
            try linkService.unlink(identifier, owner: owner)
        } catch {
            linkErrorMessage = error.localizedDescription
        }
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

    /// `PullRequestLinkService` owns the mapping; this keeps the view-model-facing name its
    /// companions and tests already use.
    static func makeSummary(from detail: PullRequestDetail, linkedAt: Date = Date()) -> PullRequestSummary {
        PullRequestLinkService.makeSummary(from: detail, linkedAt: linkedAt)
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
        case .rateLimited, .requestFailed, .responseTooLarge, .decodingFailed, .queryTooExpensive, .transport:
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
