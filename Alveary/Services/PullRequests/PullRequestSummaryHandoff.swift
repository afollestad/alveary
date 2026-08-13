import Foundation

/// The rows the `alveary_host` `list_involved_prs` tool most recently returned, held so `link_pr`
/// can store one as its snapshot instead of paying a second fetch for a pull request the same
/// search just proved reachable. This is the summary half of `PullRequestLinkService.link`'s
/// `detail:` handover: the link invariant is that a stored snapshot came from GitHub, not that
/// the link call is personally the fetcher — and the search row is the richer snapshot, carrying
/// involvement flags and an `updatedAt` a detail-derived summary has to guess at.
///
/// Entries expire after `maxAge` so a link never stores a row from a search nobody would still
/// call recent. The window is generous because the flow this serves — a scheduled run listing
/// pull requests, then fanning out one thread-and-link pair per row — spans many model turns.
@MainActor
final class PullRequestSummaryHandoff {
    private var entries: [PullRequestIdentifier: Entry] = [:]
    private let now: () -> Date
    private let maxAge: TimeInterval

    init(now: @escaping () -> Date = Date.init, maxAge: TimeInterval = 30 * 60) {
        self.now = now
        self.maxAge = maxAge
    }

    /// Records every row a successful list fetch returned — including rows the tool's filter or
    /// limit is about to drop, because the fetch proved each one reachable and that proof is all
    /// a reader relies on.
    func record(_ summaries: [PullRequestSummary]) {
        let observedAt = now()
        // Prune on write so an app left running does not accumulate every row it ever listed.
        entries = entries.filter { observedAt.timeIntervalSince($0.value.observedAt) < maxAge }
        for summary in summaries {
            entries[summary.id] = Entry(summary: summary, observedAt: observedAt)
        }
    }

    /// The identifier's row from a recent enough fetch, or nil when the caller must fetch itself.
    func summary(for identifier: PullRequestIdentifier) -> PullRequestSummary? {
        guard let entry = entries[identifier],
              now().timeIntervalSince(entry.observedAt) < maxAge else {
            return nil
        }
        return entry.summary
    }
}

private extension PullRequestSummaryHandoff {
    struct Entry {
        let summary: PullRequestSummary
        let observedAt: Date
    }
}
