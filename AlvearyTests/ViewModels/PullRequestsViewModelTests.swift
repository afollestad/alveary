import XCTest

@testable import Alveary

@MainActor
final class PullRequestsViewModelTests: XCTestCase {
    func testRefreshPopulatesItemsAndPhase() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            warnings: ["partial"]
        ))
        let viewModel = makePullRequestsViewModel(service: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.loadPhase, .loaded)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.warnings, ["partial"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.lastRefreshedAt)
    }

    func testRefreshForScreenThrottlesWithinInterval() async {
        let service = StubPullRequestsService()
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let viewModel = makePullRequestsViewModel(service: service, now: { currentDate })

        await viewModel.refreshForScreen()
        await viewModel.refreshForScreen()
        XCTAssertEqual(service.listCallCount, 1)

        currentDate = currentDate.addingTimeInterval(PullRequestsViewModel.refreshInterval + 1)
        await viewModel.refreshForScreen()
        XCTAssertEqual(service.listCallCount, 2)
    }

    func testTabBucketing() async {
        let service = StubPullRequestsService()
        let authored = makePullRequestSummary(number: 1, isAuthored: true)
        let requested = makePullRequestSummary(number: 2, isReviewRequested: true)
        let reviewed = makePullRequestSummary(number: 3, hasReviewed: true)
        let authoredAndReviewing = makePullRequestSummary(number: 4, isAuthored: true, isReviewRequested: true)
        service.listResult = .success(PullRequestListResult(
            summaries: [authored, requested, reviewed, authoredAndReviewing],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [1, 2, 3, 4])
        XCTAssertEqual(viewModel.visibleRows(for: .authored).map(\.id.number), [1, 4])
        XCTAssertEqual(viewModel.visibleRows(for: .reviewing).map(\.id.number), [2, 3, 4])
    }

    func testReviewingSectionsSplitPendingFromPreviouslyReviewed() async {
        let service = StubPullRequestsService()
        let pending = makePullRequestSummary(number: 1, isReviewRequested: true)
        // Re-requested reviews count as pending even when a past review exists.
        let reRequested = makePullRequestSummary(number: 2, isReviewRequested: true, hasReviewed: true)
        let previous = makePullRequestSummary(number: 3, hasReviewed: true)
        service.listResult = .success(PullRequestListResult(
            summaries: [pending, reRequested, previous],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        let sections = viewModel.visibleSections(for: .reviewing)
        XCTAssertEqual(sections.map(\.title), ["Pending review", "Previously reviewed"])
        XCTAssertEqual(sections[0].rows.map(\.id.number), [1, 2])
        XCTAssertEqual(sections[1].rows.map(\.id.number), [3])
    }

    func testStatusRepositoryAndSearchFilters() async {
        let service = StubPullRequestsService()
        let draft = makePullRequestSummary(number: 1, repo: "octo/alpha", title: "Draft parser", status: .draft, isAuthored: true)
        let merged = makePullRequestSummary(number: 2, repo: "octo/beta", title: "Merge cleanup", status: .merged, isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [draft, merged], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        viewModel.toggleStatusFilter(.draft)
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [1])

        // Multi-select: adding a second status widens the result.
        viewModel.toggleStatusFilter(.merged)
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [1, 2])

        viewModel.clearStatusFilters()
        viewModel.toggleRepositoryFilter("octo/beta")
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [2])
        XCTAssertFalse(viewModel.showsRepositoryInRows)

        viewModel.toggleRepositoryFilter("octo/alpha")
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [1, 2])
        XCTAssertTrue(viewModel.showsRepositoryInRows)

        viewModel.clearRepositoryFilters()
        viewModel.searchQuery = "parser"
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [1])

        viewModel.searchQuery = "octo/beta"
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [2])
    }

    func testRepositoryFilterOptionsAndNormalization() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, repo: "octo/beta", isAuthored: true),
                makePullRequestSummary(number: 2, repo: "octo/alpha", isAuthored: true)
            ],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.repositoryFilterOptions, ["octo/alpha", "octo/beta"])

        viewModel.toggleRepositoryFilter("octo/beta")
        viewModel.toggleRepositoryFilter("octo/alpha")
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 2, repo: "octo/alpha", isAuthored: true)],
            warnings: []
        ))
        await viewModel.refresh()

        // The vanished repository is pruned; the surviving selection stays.
        XCTAssertEqual(viewModel.selectedRepositories, ["octo/alpha"])
    }

    func testFailureWithoutItemsMapsToUnavailableReason() async {
        for (error, reason) in [
            (PullRequestsServiceError.ghNotInstalled, PullRequestsUnavailableReason.notInstalled),
            (.notAuthenticated, .notAuthenticated),
            (.rateLimited, .rateLimited),
            (.transport("boom"), .failed("boom"))
        ] {
            let service = StubPullRequestsService()
            service.listResult = .failure(error)
            let viewModel = makePullRequestsViewModel(service: service)

            await viewModel.refresh()

            XCTAssertEqual(viewModel.loadPhase, .unavailable(reason))
            XCTAssertNil(viewModel.errorMessage)
        }
    }

    func testFailureWithStaleItemsKeepsRowsAndShowsBanner() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            warnings: []
        ))
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let viewModel = makePullRequestsViewModel(service: service, now: { currentDate })
        await viewModel.refresh()
        currentDate = currentDate.addingTimeInterval(120)

        service.listResult = .failure(.rateLimited)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.loadPhase, .loaded)
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRequestDetailsTracksSelection() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isDetailActive(summary.id))
        viewModel.requestDetails(summary)
        XCTAssertTrue(viewModel.isDetailActive(summary.id))
    }

    func testDismissWarningsClearsThem() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(summaries: [], warnings: ["saml"]))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.warnings, ["saml"])
        viewModel.dismissWarnings()
        XCTAssertEqual(viewModel.warnings, [])
    }

    func testVisibleRowsOrderByRecency() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, status: .closed, updatedAt: Date(timeIntervalSince1970: 4_000), isAuthored: true),
                makePullRequestSummary(number: 2, status: .open, updatedAt: Date(timeIntervalSince1970: 1_000), isAuthored: true),
                makePullRequestSummary(number: 3, status: .merged, updatedAt: Date(timeIntervalSince1970: 3_000), isAuthored: true),
                makePullRequestSummary(number: 4, status: .draft, updatedAt: Date(timeIntervalSince1970: 2_000), isAuthored: true),
                makePullRequestSummary(number: 5, status: .open, updatedAt: Date(timeIntervalSince1970: 5_000), isAuthored: true)
            ],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        // The row's displayed date orders the list, newest first, regardless of status.
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.id.number), [5, 1, 3, 4, 2])
    }

    func testRestoresPersistedTabAndFilters() {
        let settings = InMemorySettingsService()
        settings.update {
            $0.pullRequestsSelectedTab = "Reviewing"
            $0.pullRequestsStatusFilters = [.open, .draft]
            $0.pullRequestsRepositoryFilters = ["octo/alpha"]
        }

        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService(), settingsService: settings)

        XCTAssertEqual(viewModel.selectedFilter, .reviewing)
        XCTAssertEqual(viewModel.selectedStatuses, [.open, .draft])
        XCTAssertEqual(viewModel.selectedRepositories, ["octo/alpha"])
    }

    func testInvalidPersistedTabFallsBackToAll() {
        let settings = InMemorySettingsService()
        settings.update {
            $0.pullRequestsSelectedTab = "Bogus"
        }

        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService(), settingsService: settings)

        XCTAssertEqual(viewModel.selectedFilter, .all)
    }

    func testSelectFilterPersistsTabAndSkipsRedundantWrites() {
        let settings = InMemorySettingsService()
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService(), settingsService: settings)

        viewModel.selectFilter(.authored)

        XCTAssertEqual(viewModel.selectedFilter, .authored)
        XCTAssertEqual(settings.current.pullRequestsSelectedTab, "Authored")

        let updateCount = settings.updateCount
        viewModel.selectFilter(.authored)
        XCTAssertEqual(settings.updateCount, updateCount)
    }

    func testFilterTogglesAndClearsPersist() {
        let settings = InMemorySettingsService()
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService(), settingsService: settings)

        viewModel.toggleStatusFilter(.merged)
        viewModel.toggleRepositoryFilter("octo/alpha")

        XCTAssertEqual(settings.current.pullRequestsStatusFilters, [.merged])
        XCTAssertEqual(settings.current.pullRequestsRepositoryFilters, ["octo/alpha"])

        viewModel.clearStatusFilters()
        viewModel.clearRepositoryFilters()

        XCTAssertEqual(settings.current.pullRequestsStatusFilters, [])
        XCTAssertEqual(settings.current.pullRequestsRepositoryFilters, [])
    }

    func testCancelledRefreshSurfacesNoErrorOrUnavailableState() async {
        let service = StubPullRequestsService()
        // Shell teardown surfaces cancellation as a wrapped service error.
        service.listResult = .failure(.transport("Command was cancelled"))
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        let viewModel = makePullRequestsViewModel(service: service)

        let refreshTask = Task {
            await viewModel.refresh()
        }
        for _ in 0..<2_000 {
            if viewModel.isRefreshing {
                break
            }
            await Task.yield()
        }
        refreshTask.cancel()
        gate.open()
        await refreshTask.value

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.loadPhase, .loading)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testRefreshOfPopulatedListAppliesTheBatchedResultOnce() async {
        let service = StubPullRequestsService()
        let original = makePullRequestSummary(number: 1, title: "Original", isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [original], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.items.map(\.title), ["Original"])
        XCTAssertEqual(service.listCallCount, 1)

        // Second refresh: the single batched request is held open mid-flight.
        let updated = makePullRequestSummary(number: 1, title: "Updated", isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [updated], warnings: []))
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        let refreshTask = Task {
            await viewModel.refresh()
        }
        for _ in 0..<200 {
            await Task.yield()
        }
        // The populated list must not repaint mid-refresh — no double load.
        XCTAssertEqual(viewModel.items.map(\.title), ["Original"])

        gate.open()
        await refreshTask.value
        XCTAssertEqual(viewModel.items.map(\.title), ["Updated"])
        // All three involvement buckets travel in that one request.
        XCTAssertEqual(service.listCallCount, 2)
    }

    func testCachedListPaintsBeforeNetworkAndRefreshSaves() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-cache-test-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        let cache = PullRequestsListCache(fileURL: cacheURL)
        await cache.save([makePullRequestSummary(number: 9, isAuthored: true)])

        let service = StubPullRequestsService()
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 10, isAuthored: true)],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service, listCache: cache)

        let screenTask = Task {
            await viewModel.refreshForScreen()
        }
        // Cached rows paint while the network request is held open.
        for _ in 0..<2_000 {
            if viewModel.items.map(\.id.number) == [9] {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(viewModel.items.map(\.id.number), [9])
        XCTAssertEqual(viewModel.loadPhase, .loaded)

        gate.open()
        await screenTask.value
        XCTAssertEqual(viewModel.items.map(\.id.number), [10])

        // The refresh persists the fresh list for the next launch.
        for _ in 0..<2_000 {
            if await cache.load()?.map(\.id.number) == [10] {
                break
            }
            await Task.yield()
        }
        let persisted = await cache.load()
        XCTAssertEqual(persisted?.map(\.id.number), [10])
    }

    func testCorruptOrMissingCacheLoadsAsNil() async {
        let missing = PullRequestsListCache(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("pr-cache-missing-\(UUID().uuidString).json")
        )
        let missingResult = await missing.load()
        XCTAssertNil(missingResult)

        let corruptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-cache-corrupt-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: corruptURL)
        }
        try? Data("not json".utf8).write(to: corruptURL)
        let corrupt = PullRequestsListCache(fileURL: corruptURL)
        let corruptResult = await corrupt.load()
        XCTAssertNil(corruptResult)
    }

    func testVisibleSectionsBucketAllTabByInvolvement() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, isAuthored: true, isReviewRequested: true),
                makePullRequestSummary(number: 2, isReviewRequested: true),
                makePullRequestSummary(number: 3, hasReviewed: true)
            ],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        let sections = viewModel.visibleSections(for: .all)
        XCTAssertEqual(sections.map(\.title), ["Authored", "Pending review", "Previously reviewed"])
        // Authored wins when a PR is both authored and review-requested.
        XCTAssertEqual(sections[0].rows.map(\.id.number), [1])
        XCTAssertEqual(sections[1].rows.map(\.id.number), [2])
        XCTAssertEqual(sections[2].rows.map(\.id.number), [3])

        // Authored tab stays one untitled flat section.
        let authored = viewModel.visibleSections(for: .authored)
        XCTAssertEqual(authored.count, 1)
        XCTAssertNil(authored[0].title)
    }

    func testCompactRelativeAge() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let cases: [(TimeInterval, String)] = [
            (0, "now"),
            (59, "now"),
            (60, "1m"),
            (5 * 60, "5m"),
            (3 * 3_600, "3h"),
            (2 * 86_400, "2d"),
            (3 * 7 * 86_400, "3w"),
            (35 * 86_400, "1mo"),
            (11 * 30 * 86_400, "11mo"),
            (2 * 365 * 86_400, "2y")
        ]
        for (interval, expected) in cases {
            XCTAssertEqual(
                compactRelativeAge(from: now.addingTimeInterval(-interval), relativeTo: now),
                expected,
                "interval \(interval)"
            )
        }
        // Future dates clamp to "now" instead of going negative.
        XCTAssertEqual(compactRelativeAge(from: now.addingTimeInterval(600), relativeTo: now), "now")
    }
}
