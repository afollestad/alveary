import Foundation

// MARK: - Filtering

extension PullRequestsViewModel {
    var repositoryFilterOptions: [String] {
        Set(items.map(\.repositoryNameWithOwner)).sorted()
    }

    /// Whether the menu narrows the list at all. True for the packaged `.open` default too — the
    /// list genuinely is narrowed there, and the highlighted button is what points at why merged
    /// and closed pull requests are absent.
    var hasActiveMenuFilters: Bool {
        selectedStatusFilter != .all || !selectedRepositories.isEmpty
    }

    /// Rows hide the repository text only while the filter narrows to one repository.
    var showsRepositoryInRows: Bool {
        selectedRepositories.count != 1
    }

    func clearRepositoryFilters() {
        guard !selectedRepositories.isEmpty else {
            return
        }
        selectedRepositories = []
        persistRepositoryFilters()
    }

    func toggleRepositoryFilter(_ nameWithOwner: String) {
        if selectedRepositories.contains(nameWithOwner) {
            selectedRepositories.remove(nameWithOwner)
        } else {
            selectedRepositories.insert(nameWithOwner)
        }
        persistRepositoryFilters()
    }

    var hasActiveNarrowing: Bool {
        hasActiveMenuFilters || !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Filtered rows ordered by recency — the date each row displays — so the list
    /// reads naturally top-to-bottom. Applied here so every tab and section
    /// inherits it, with a stable key breaking timestamp ties.
    ///
    /// Memoized on its own inputs: the screen calls this once per body pass, and a root
    /// invalidation from anywhere re-runs that pass. Every input is read before the cache
    /// is consulted so `@Observable` still registers the same dependencies, and the cache
    /// itself is `@ObservationIgnored`, so filling it publishes nothing.
    func visibleRows(for tab: PullRequestsFilter) -> [PullRequestSummary] {
        let key = VisibleRowsCacheKey(
            tab: tab,
            status: selectedStatusFilter,
            repositories: selectedRepositories,
            searchQuery: searchQuery.trimmingCharacters(in: .whitespaces),
            items: items
        )
        if let visibleListCache, visibleListCache.key == key {
            return visibleListCache.rows
        }
        let rows = computeVisibleRows(for: tab)
        visibleListCache = VisibleListCache(key: key, rows: rows)
        return rows
    }

    private func computeVisibleRows(for tab: PullRequestsFilter) -> [PullRequestSummary] {
        items.filter { summary in
            matchesTab(summary, tab: tab)
                // Kept alongside the search qualifier so the rows can never contradict the
                // selected filter: between a status change and its reload `items` still holds
                // the previous search, and `applyStatus` writes a close or reopen with no
                // reload behind it at all.
                && selectedStatusFilter.matches(summary.status)
                && matchesRepositoryFilter(summary)
                && matchesSearch(summary)
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.displayKey < rhs.id.displayKey
        }
    }

    /// Visible rows grouped into titled sections for the current tab. Empty sections
    /// drop out; the Authored tab stays a flat, untitled list. In the All tab each
    /// row lands in exactly one bucket — your own PRs count as Authored even when
    /// your review is also requested.
    ///
    /// Memoized like `visibleRows(for:)`, and for a second reason: returning the same
    /// arrays lets `PullRequestsSectionedList`'s equality take Swift's shared-buffer fast
    /// path instead of comparing every row.
    func visibleSections(for tab: PullRequestsFilter) -> [PullRequestListSection] {
        // Leaves `visibleListCache` holding this tab's entry, so the sections below
        // attach to the rows they were built from.
        let rows = visibleRows(for: tab)
        if let sections = visibleListCache?.sections {
            return sections
        }
        let sections = buildSections(tab: tab, rows: rows)
        visibleListCache?.sections = sections
        return sections
    }

    private func buildSections(
        tab: PullRequestsFilter,
        rows: [PullRequestSummary]
    ) -> [PullRequestListSection] {
        let sections: [PullRequestListSection]
        switch tab {
        case .authored:
            sections = [PullRequestListSection(id: "authored-flat", title: nil, rows: rows)]
        case .reviewing:
            sections = [
                PullRequestListSection(
                    id: "reviewing-pending",
                    title: "Pending review",
                    rows: rows.filter(\.isReviewRequested)
                ),
                PullRequestListSection(
                    id: "reviewing-previous",
                    title: "Previously reviewed",
                    rows: rows.filter { !$0.isReviewRequested }
                )
            ]
        case .all:
            sections = [
                PullRequestListSection(
                    id: "all-authored",
                    title: "Authored",
                    rows: rows.filter(\.isAuthored)
                ),
                PullRequestListSection(
                    id: "all-pending",
                    title: "Pending review",
                    rows: rows.filter { !$0.isAuthored && $0.isReviewRequested }
                ),
                PullRequestListSection(
                    id: "all-previous",
                    title: "Previously reviewed",
                    rows: rows.filter { !$0.isAuthored && !$0.isReviewRequested }
                )
            ]
        }
        return sections.filter { !$0.rows.isEmpty }
    }

    /// Keeps the repository menu honest when a refresh drops selected repositories.
    /// Deliberately not persisted: only explicit user toggles write settings, so a
    /// repository that is temporarily absent from one fetch can reappear selected.
    func normalizeRepositoryFilter() {
        selectedRepositories.formIntersection(repositoryFilterOptions)
    }

    private func persistRepositoryFilters() {
        let repositories = selectedRepositories
        settingsService?.update { $0.pullRequestsRepositoryFilters = repositories }
    }

    private func matchesTab(_ summary: PullRequestSummary, tab: PullRequestsFilter) -> Bool {
        switch tab {
        case .all:
            return true
        case .reviewing:
            return summary.isReviewRequested || summary.hasReviewed
        case .authored:
            return summary.isAuthored
        }
    }

    /// Moves the detail selection to the adjacent row in visual order, clamping at
    /// the ends; with no active selection, Down selects the first row and Up the last.
    /// Callers pass the rows `visibleRows(for:)` produced, so arrow keys walk exactly
    /// what the screen shows.
    @discardableResult
    func selectAdjacentRow(in rows: [PullRequestSummary], forward: Bool) -> PullRequestIdentifier? {
        guard !rows.isEmpty else {
            return nil
        }
        let nextIndex: Int
        if let currentIndex = rows.firstIndex(where: { isDetailActive($0.id) }) {
            nextIndex = min(max(currentIndex + (forward ? 1 : -1), 0), rows.count - 1)
        } else {
            nextIndex = forward ? 0 : rows.count - 1
        }
        let summary = rows[nextIndex]
        requestDetails(summary)
        return summary.id
    }

    private func matchesRepositoryFilter(_ summary: PullRequestSummary) -> Bool {
        selectedRepositories.isEmpty || selectedRepositories.contains(summary.repositoryNameWithOwner)
    }

    private func matchesSearch(_ summary: PullRequestSummary) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return true
        }
        return summary.title.localizedCaseInsensitiveContains(query)
            || summary.repositoryNameWithOwner.localizedCaseInsensitiveContains(query)
            || summary.authorLogin.localizedCaseInsensitiveContains(query)
            || summary.headRefName.localizedCaseInsensitiveContains(query)
    }
}

/// The shaped list for one set of inputs. Sections fill in on first use, so a screen that
/// only walks rows never pays for the bucketing.
struct VisibleListCache {
    let key: VisibleRowsCacheKey
    let rows: [PullRequestSummary]
    var sections: [PullRequestListSection]?
}

/// Every input `visibleRows(for:)` reads. `items` compares by shared buffer while the list
/// is unchanged, so a cache hit costs no per-row work.
struct VisibleRowsCacheKey: Equatable {
    let tab: PullRequestsFilter
    let status: PullRequestStatusFilter
    let repositories: Set<String>
    let searchQuery: String
    let items: [PullRequestSummary]
}
