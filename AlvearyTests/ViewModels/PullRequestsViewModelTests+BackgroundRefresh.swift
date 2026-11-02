import Foundation
import XCTest

@testable import Alveary

// Rows the status menu's background poll read, arriving through `.pullRequestBucketRefreshed`.
extension PullRequestsViewModelTests {
    func testBackgroundRefreshReplacesTheBucketAndSavesTheCache() async throws {
        let fixture = try await BackgroundRefreshFixture.loaded()
        defer { fixture.removeCache() }
        let fresh = makePullRequestSummary(number: 7, title: "Fresh", isReviewRequested: true)

        fixture.post(fixture.refresh(summaries: [fresh]))

        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.summaries.map(\.id), [fresh.id])
        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.fetchedAt, fixture.later)
        XCTAssertTrue(fixture.viewModel.items.contains { $0.id == fresh.id })
        XCTAssertFalse(fixture.viewModel.items.contains { $0.id == fixture.held.id })
        try await waitForPullRequests("the list cache takes the fresh bucket") {
            await fixture.cache.load(filter: .open)?[.reviewRequested]?.map(\.id) == [fresh.id]
        }
    }

    func testBackgroundRefreshUnderAnotherStatusIsIgnored() async throws {
        let fixture = try await BackgroundRefreshFixture.loaded()
        defer { fixture.removeCache() }

        fixture.post(fixture.refresh(summaries: [], status: .merged))

        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.summaries.map(\.id), [fixture.held.id])
    }

    func testBackgroundRefreshNeverShrinksABucketPagedPastPageOne() async throws {
        let fixture = try await BackgroundRefreshFixture.loaded()
        defer { fixture.removeCache() }
        let paged = (1...(PullRequestsViewModel.listPageSize + 5)).map {
            makePullRequestSummary(number: 100 + $0, isReviewRequested: true)
        }
        fixture.viewModel.bucketStates[.reviewRequested]?.summaries = paged

        fixture.post(fixture.refresh(summaries: [makePullRequestSummary(number: 7, isReviewRequested: true)]))

        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.summaries.count, paged.count)
    }

    func testBackgroundRefreshOlderThanTheHeldBucketIsIgnored() async throws {
        let fixture = try await BackgroundRefreshFixture.loaded()
        defer { fixture.removeCache() }

        fixture.post(fixture.refresh(summaries: [], fetchedAt: fixture.earlier))

        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.summaries.map(\.id), [fixture.held.id])
    }

    func testBackgroundRefreshWaitsForTheCachedPaint() async {
        let fixture = BackgroundRefreshFixture()
        defer { fixture.removeCache() }

        fixture.post(fixture.refresh(summaries: [makePullRequestSummary(number: 7, isReviewRequested: true)]))

        XCTAssertNil(fixture.viewModel.bucketStates[.reviewRequested])
    }

    func testReplacingOneCachedBucketKeepsTheOthersUnderTheSameStatusOnly() async {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-cache-replace-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = PullRequestsListCache(fileURL: cacheURL)
        let authored = makePullRequestSummary(number: 1, isAuthored: true)
        let requested = makePullRequestSummary(number: 2, isReviewRequested: true)
        await cache.save([.authored: [authored]], filter: .open)

        await cache.replaceBucket(.reviewRequested, with: [requested], filter: .open)
        let sameStatus = await cache.load(filter: .open)
        XCTAssertEqual(sameStatus?[.authored]?.map(\.id), [authored.id])
        XCTAssertEqual(sameStatus?[.reviewRequested]?.map(\.id), [requested.id])

        await cache.replaceBucket(.reviewRequested, with: [requested], filter: .all)
        let otherStatus = await cache.load(filter: .all)
        XCTAssertNil(otherStatus?[.authored])
        XCTAssertEqual(otherStatus?[.reviewRequested]?.map(\.id), [requested.id])
    }

    private func waitForPullRequests(
        _ description: String,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        try await scheduledTaskLifecycleWaitUntil(description, condition: condition)
    }
}

@MainActor
private struct BackgroundRefreshFixture {
    let service = StubPullRequestsService()
    let notificationCenter = NotificationCenter()
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pr-cache-background-\(UUID().uuidString).json")
    let cache: PullRequestsListCache
    let viewModel: PullRequestsViewModel
    let held = makePullRequestSummary(number: 3, title: "Held", isReviewRequested: true)
    let earlier = Date(timeIntervalSince1970: 1_000)
    let loadedAt = Date(timeIntervalSince1970: 2_000)
    let later = Date(timeIntervalSince1970: 3_000)

    init() {
        cache = PullRequestsListCache(fileURL: cacheURL)
        service.listResult = .success(PullRequestListResult(summaries: [held], warnings: []))
        let loadedAt = loadedAt
        viewModel = makePullRequestsViewModel(
            service: service,
            listCache: cache,
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            now: { loadedAt }
        )
    }

    /// The screen has painted and loaded its tab, so the review bucket holds `held` from `loadedAt`.
    ///
    /// Waits for that load's own cache save too: saves run detached, so one still pending could
    /// land after a test's later save and read as the background refresh having been lost.
    static func loaded() async throws -> Self {
        let fixture = Self()
        await fixture.viewModel.refreshForScreen()
        XCTAssertEqual(fixture.viewModel.bucketStates[.reviewRequested]?.summaries.map(\.id), [fixture.held.id])
        let cache = fixture.cache
        let heldID = fixture.held.id
        try await scheduledTaskLifecycleWaitUntil("the screen's own load is saved") {
            await cache.load(filter: .open)?[.reviewRequested]?.map(\.id) == [heldID]
        }
        return fixture
    }

    func removeCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func refresh(
        summaries: [PullRequestSummary],
        status: PullRequestStatusFilter = .open,
        fetchedAt: Date? = nil
    ) -> PullRequestBucketRefresh {
        PullRequestBucketRefresh(
            bucket: .reviewRequested,
            status: status,
            summaries: summaries,
            pageInfo: nil,
            fetchedAt: fetchedAt ?? later
        )
    }

    func post(_ refresh: PullRequestBucketRefresh) {
        notificationCenter.post(
            name: .pullRequestBucketRefreshed,
            object: nil,
            userInfo: [PullRequestBucketRefresh.userInfoKey: refresh]
        )
    }
}
