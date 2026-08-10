import Foundation
import XCTest

@testable import Alveary

// The list's "Load more" footer: which buckets it pages, how the extra rows land, and what it
// must not disturb — the page-one freshness throttle and the cached first page.
@MainActor
extension PullRequestsViewModelTests {
    func testLoadMoreAppendsOnOneBarrierWithoutTouchingTheFreshnessStamp() async {
        let service = StubPullRequestsService()
        service.listResult = pagedAuthoredResult(numbers: [1, 2], endCursor: "a2", hasNextPage: true)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        XCTAssertTrue(viewModel.canLoadMore(for: .authored))
        let fetchedAt = viewModel.bucketStates[.authored]?.fetchedAt

        service.listResult = pagedAuthoredResult(numbers: [3, 4], endCursor: "a4", hasNextPage: false)
        await viewModel.loadMore()

        let request = service.listRequests.last
        XCTAssertEqual(request?.options.cursors, [.authored: "a2"])
        XCTAssertEqual(viewModel.items.map(\.id.number), [1, 2, 3, 4])
        XCTAssertEqual(viewModel.bucketStates[.authored]?.endCursor, "a4")
        XCTAssertFalse(viewModel.canLoadMore(for: .authored))
        // Paging deeper must not re-satisfy the throttle that governs page one.
        XCTAssertEqual(viewModel.bucketStates[.authored]?.fetchedAt, fetchedAt)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    /// A cursor is opaque and belongs to the search that produced it, so the footer must not
    /// survive a status change and offer to page the previous search's position.
    func testAStatusChangeDropsThePagingPosition() async {
        let service = StubPullRequestsService()
        service.listResult = pagedAuthoredResult(numbers: [1], endCursor: "a1", hasNextPage: true)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()
        XCTAssertTrue(viewModel.canLoadMore(for: .authored))

        viewModel.markAllBucketsStale()

        XCTAssertFalse(viewModel.canLoadMore(for: .authored))
        XCTAssertNil(viewModel.bucketStates[.authored]?.endCursor)
        // The rows stay on screen; only the position is dropped.
        XCTAssertEqual(viewModel.items.map(\.id.number), [1])
    }

    func testLoadMoreDedupesAgainstTheRowsAlreadyHeld() async {
        let service = StubPullRequestsService()
        service.listResult = pagedAuthoredResult(numbers: [1, 2], endCursor: "a2", hasNextPage: true)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        // A row updated mid-pagination can repeat across pages, exactly as it can on github.com.
        service.listResult = pagedAuthoredResult(numbers: [2, 3], endCursor: "a3", hasNextPage: false)
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.items.map(\.id.number), [1, 2, 3])
    }

    func testLoadMoreOnlyPagesTheBucketsThatHaveMore() async {
        let service = StubPullRequestsService()
        service.listResultsByBucket = [
            .reviewRequested: pagedResult(bucket: .reviewRequested, numbers: [1], endCursor: "r1", hasNextPage: true),
            .reviewed: pagedResult(bucket: .reviewed, numbers: [2], endCursor: "v1", hasNextPage: false)
        ]
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.reviewing)
        await viewModel.refreshForScreen()

        let afterFirstPage = service.listRequests.count
        await viewModel.loadMore()

        XCTAssertEqual(service.listRequests.count, afterFirstPage + 1)
        XCTAssertEqual(service.listRequests.last?.buckets, [.reviewRequested])
    }

    func testLoadMoreKeepsTheFooterAfterAFailureSoItDoublesAsRetry() async {
        let service = StubPullRequestsService()
        service.listResult = pagedAuthoredResult(numbers: [1], endCursor: "a1", hasNextPage: true)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        service.listResult = .failure(.rateLimited)
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.items.map(\.id.number), [1])
        XCTAssertEqual(viewModel.errorMessage, PullRequestsServiceError.rateLimited.localizedDescription)
        XCTAssertTrue(viewModel.canLoadMore(for: .authored))
    }

    func testACancelledLoadMoreAppliesNothing() async {
        let service = StubPullRequestsService()
        service.listResult = pagedAuthoredResult(numbers: [1], endCursor: "a1", hasNextPage: true)
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        let gate = PullRequestsServiceGate()
        service.listGate = gate
        service.listResult = pagedAuthoredResult(numbers: [2], endCursor: "a2", hasNextPage: false)
        let task = Task { await viewModel.loadMore() }
        await waitFor { service.listRequests.count == 2 }
        // While the page is in flight its bucket is in `inFlightBuckets`, so `canLoadMore` reads
        // false; `isLoadingMore` is what the screen ORs in to keep the footer's spinner mounted.
        XCTAssertTrue(viewModel.isLoadingMore)
        XCTAssertFalse(viewModel.canLoadMore(for: .authored))
        task.cancel()
        gate.open()
        await task.value

        XCTAssertEqual(viewModel.items.map(\.id.number), [1])
        XCTAssertEqual(viewModel.bucketStates[.authored]?.endCursor, "a1")
    }

    /// The cache exists to fill the first frame, and painting it is followed by a page-one fetch
    /// that replaces the bucket — so persisting appended pages would only store rows the next load
    /// throws away.
    func testTheListCacheKeepsOnlyTheFirstPage() async {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-load-more-cache-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        let cache = PullRequestsListCache(fileURL: cacheURL)
        let service = StubPullRequestsService()
        let firstPage = (1...PullRequestsViewModel.listPageSize).map {
            makePullRequestSummary(number: $0, isAuthored: true)
        }
        service.listResult = .success(PullRequestListResult(
            summariesByBucket: [.authored: firstPage],
            warnings: [],
            pageInfoByBucket: [.authored: PullRequestListPageInfo(
                endCursor: "a50",
                hasNextPage: true,
                rowCursors: firstPage.map { "a\($0.id.number)" }
            )]
        ))
        let viewModel = makePullRequestsViewModel(service: service, listCache: cache)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        // Drain the page-one save first, so the file the assertion reads can only have been
        // written by the load-more that follows.
        for _ in 0..<2_000 where await cache.load(filter: .open) == nil {
            await Task.yield()
        }
        try? FileManager.default.removeItem(at: cacheURL)

        service.listResult = pagedAuthoredResult(numbers: [51, 52], endCursor: "a52", hasNextPage: false)
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.items.count, PullRequestsViewModel.listPageSize + 2)

        var cached: [PullRequestInvolvementBucket: [PullRequestSummary]]?
        for _ in 0..<2_000 where cached == nil {
            cached = await cache.load(filter: .open)
            await Task.yield()
        }
        XCTAssertEqual(cached?[.authored]?.count, PullRequestsViewModel.listPageSize)
        XCTAssertFalse(cached?[.authored]?.contains { $0.id.number == 51 } ?? true)
    }
}

private extension PullRequestsViewModelTests {
    func pagedAuthoredResult(
        numbers: [Int],
        endCursor: String,
        hasNextPage: Bool
    ) -> Result<PullRequestListResult, PullRequestsServiceError> {
        pagedResult(bucket: .authored, numbers: numbers, endCursor: endCursor, hasNextPage: hasNextPage)
    }

    func pagedResult(
        bucket: PullRequestInvolvementBucket,
        numbers: [Int],
        endCursor: String,
        hasNextPage: Bool
    ) -> Result<PullRequestListResult, PullRequestsServiceError> {
        let summaries = numbers.map { number in
            makePullRequestSummary(
                number: number,
                isAuthored: bucket == .authored,
                isReviewRequested: bucket == .reviewRequested,
                hasReviewed: bucket == .reviewed
            )
        }
        return .success(PullRequestListResult(
            summariesByBucket: [bucket: summaries],
            warnings: [],
            pageInfoByBucket: [bucket: PullRequestListPageInfo(
                endCursor: endCursor,
                hasNextPage: hasNextPage,
                rowCursors: numbers.map { "\(bucket.rawValue)-\($0)" }
            )]
        ))
    }
}
