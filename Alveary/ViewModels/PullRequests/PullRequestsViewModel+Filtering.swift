import Foundation

// MARK: - Filtering

extension PullRequestsViewModel {
    /// What the search field shows, republished on every keystroke so typing stays responsive.
    /// The list shapes from `activeSearchQuery` instead, which trails this by `searchDebounce`.
    ///
    /// Computed over storage so that assigning it — from the field's binding, a test, or a
    /// snapshot fixture — always schedules the commit; an `onChange` in the view would miss the
    /// last two.
    var searchQuery: String {
        get { typedSearchQuery }
        set {
            guard newValue != typedSearchQuery else {
                return
            }
            typedSearchQuery = newValue
            scheduleSearchCommit()
        }
    }

    /// Restarts the debounce for the keystroke just typed. The pending commit is cancelled rather
    /// than left to fire, so a burst of keystrokes reshapes the list once.
    private func scheduleSearchCommit() {
        searchCommitTask?.cancel()
        searchCommitGeneration += 1
        guard searchDebounce != .zero else {
            commitSearchQuery()
            return
        }
        let generation = searchCommitGeneration
        let delay = searchDebounce
        searchCommitTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  self.searchCommitGeneration == generation else {
                return
            }
            self.commitSearchQuery()
        }
    }

    private func commitSearchQuery() {
        let trimmed = typedSearchQuery.trimmingCharacters(in: .whitespaces)
        // Typing only whitespace onto a committed query changes nothing the list shapes from, so
        // publishing it would invalidate every tab's memo for an identical result.
        guard trimmed != activeSearchQuery else {
            return
        }
        activeSearchQuery = trimmed
    }

    var repositoryFilterOptions: [String] {
        knownRepositories.sorted()
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
            knownRepositories.insert(nameWithOwner)
            selectedRepositories.insert(nameWithOwner)
        }
        persistRepositoryFilters()
    }

    /// Reads the committed query, not the field's, so the empty-state copy cannot claim a
    /// narrowed list the rows have not been narrowed by yet.
    var hasActiveNarrowing: Bool {
        hasActiveMenuFilters || !activeSearchQuery.isEmpty
    }

    /// Filtered rows ordered by recency — the date each row displays — so the list
    /// reads naturally top-to-bottom. Applied here so every tab and section
    /// inherits it, with a stable key breaking timestamp ties.
    ///
    /// Memoized per tab on its own inputs: the screen calls this once per body pass, and a root
    /// invalidation from anywhere re-runs that pass. Every input is read before the cache
    /// is consulted so `@Observable` still registers the same dependencies, and the cache
    /// itself is `@ObservationIgnored`, so filling it publishes nothing.
    func visibleRows(for tab: PullRequestsFilter) -> [PullRequestSummary] {
        let key = VisibleRowsCacheKey(
            tab: tab,
            status: selectedStatusFilter,
            repositories: selectedRepositories,
            searchQuery: activeSearchQuery,
            items: items
        )
        if let cached = visibleListCaches[tab], cached.key == key {
            return cached.rows
        }
        let rows = computeVisibleRows(for: tab)
        visibleListCaches[tab] = VisibleListCache(key: key, rows: rows)
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
        // Populates this tab's entry first, so the sections below attach to the rows they
        // were built from.
        let rows = visibleRows(for: tab)
        if let sections = visibleListCaches[tab]?.sections {
            return sections
        }
        let sections = buildSections(tab: tab, rows: rows)
        visibleListCaches[tab]?.sections = sections
        return sections
    }

    /// The rendered column for the current tab: `visibleSections(for:)` flattened into one lazy
    /// stack of headings and rows, each row carrying its own precomputed strings.
    ///
    /// Memoized on top of the sections rather than beside them, keyed on the two display inputs
    /// the strings depend on. Both are read before the cache is consulted so `@Observable` still
    /// registers them; a minute tick therefore rewrites ages without touching the shaped rows.
    func visibleListItems(for tab: PullRequestsFilter) -> [PullRequestListItem] {
        // Populates this tab's entry first, so the column below attaches to the sections it was
        // built from.
        let sections = visibleSections(for: tab)
        let referenceDate = referenceDate
        let showsRepository = showsRepositoryInRows
        if let cached = visibleListCaches[tab]?.items,
           cached.referenceDate == referenceDate,
           cached.showsRepository == showsRepository {
            return cached.items
        }
        let items = PullRequestListItem.flatten(
            sections,
            showsRepository: showsRepository,
            referenceDate: referenceDate
        )
        visibleListCaches[tab]?.items = PullRequestListItemsCache(
            referenceDate: referenceDate,
            showsRepository: showsRepository,
            items: items
        )
        return items
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
        let query = activeSearchQuery
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
/// only walks rows never pays for the bucketing, and the rendered column fills in after them.
struct VisibleListCache {
    let key: VisibleRowsCacheKey
    let rows: [PullRequestSummary]
    var sections: [PullRequestListSection]?
    var items: PullRequestListItemsCache?
}

/// The flattened lazy column plus the two display inputs it was derived from.
///
/// Stamped rather than folded into `VisibleRowsCacheKey` on purpose: `referenceDate` moves every
/// minute and `showsRepositoryInRows` on any repository-filter change, and keying the *rows* on
/// either would redo the filter and sort pipeline for a change that only rewrites strings.
struct PullRequestListItemsCache {
    let referenceDate: Date
    let showsRepository: Bool
    let items: [PullRequestListItem]
}

/// Every input `visibleRows(for:)` reads. `items` compares by shared buffer while the list
/// is unchanged, so a cache hit costs no per-row work. This is what lets the tabs the user is
/// not looking at keep their own entries: each one revalidates against the current inputs
/// before it is served, so a stale entry is recomputed rather than shown.
struct VisibleRowsCacheKey: Equatable {
    let tab: PullRequestsFilter
    let status: PullRequestStatusFilter
    let repositories: Set<String>
    let searchQuery: String
    let items: [PullRequestSummary]
}
