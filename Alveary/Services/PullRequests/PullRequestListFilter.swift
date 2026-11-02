import Foundation

/// The Pull requests screen's filter popover as one value: the searched status, the repository
/// narrowing, and whether ignored rows show.
///
/// It persists as three `AppSettings` keys, which is what carries it across relaunches and lets
/// the status menu narrow its review list by the same selection the screen shows;
/// `AppSettings.pullRequestListFilter` assembles them. Both surfaces narrow through `matches` and
/// `admits` rather than predicates of their own, so the menu cannot drift from the screen.
struct PullRequestListFilter: Equatable, Sendable {
    var status: PullRequestStatusFilter
    var repositories: Set<String>
    var showsIgnored: Bool

    /// Status and repository. Status is also the GitHub search qualifier, and is compared here as
    /// well so rows can never contradict the selection: between a status change and its reload a
    /// caller still holds the previous search's rows, and a close or reopen edits a row in place.
    func matches(_ summary: PullRequestSummary) -> Bool {
        status.matches(summary.status)
            && (repositories.isEmpty || repositories.contains(summary.repositoryNameWithOwner))
    }

    /// `matches`, plus the ignore list unless ignored rows are showing.
    func admits(_ summary: PullRequestSummary, ignoredIDs: Set<PullRequestIdentifier>) -> Bool {
        matches(summary) && (showsIgnored || !ignoredIDs.contains(summary.id))
    }
}

extension AppSettings {
    var pullRequestListFilter: PullRequestListFilter {
        PullRequestListFilter(
            status: pullRequestsStatusFilter,
            repositories: pullRequestsRepositoryFilters,
            showsIgnored: pullRequestsShowIgnored
        )
    }
}
