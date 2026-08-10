import XCTest

@testable import Alveary

// Bucket-demand loading: which involvement buckets each tab fetches, and what a status change
// or a partial failure does to them.
@MainActor
extension PullRequestsViewModelTests {
    func testEachTabFetchesOnlyItsOwnBuckets() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, isAuthored: true),
                makePullRequestSummary(number: 2, isReviewRequested: true),
                makePullRequestSummary(number: 3, hasReviewed: true)
            ],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)

        await viewModel.refreshForScreen()

        XCTAssertEqual(service.listRequests.map(\.buckets), [[.authored]])
        // Only the authored bucket was asked for, so only its row is held.
        XCTAssertEqual(viewModel.items.map(\.id.number), [1])

        // Switching tabs fetches the two buckets the first tab never paid for, not all three.
        viewModel.selectFilter(.all)
        await viewModel.loadIfNeeded(for: .all)

        XCTAssertEqual(service.listRequests.count, 2)
        XCTAssertEqual(service.listRequests.last?.buckets, [.reviewRequested, .reviewed])
        XCTAssertEqual(viewModel.items.map(\.id.number).sorted(), [1, 2, 3])

        // Every bucket the Reviewing tab needs is already warm, so it issues nothing.
        viewModel.selectFilter(.reviewing)
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.listRequests.count, 2)
    }

    func testTheStatusFilterIsPushedIntoTheSearchAndReloadsTheVisibleTabOnly() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()
        XCTAssertEqual(service.listRequests.map(\.status), [.open])

        viewModel.selectStatusFilter(.merged)
        await waitFor { service.listRequests.count == 2 }

        // The visible tab reloads under the new status; the buckets it does not render wait.
        XCTAssertEqual(service.listRequests.last?.status, .merged)
        XCTAssertEqual(service.listRequests.last?.buckets, [.authored])

        // The other tabs' buckets were marked stale, so visiting one refetches it.
        viewModel.selectFilter(.reviewing)
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.listRequests.last?.status, .merged)
        XCTAssertEqual(service.listRequests.last?.buckets, [.reviewRequested, .reviewed])
    }

    func testARemoteChangeStalesTheBucketsTheVisibleTabDoesNotRender() async {
        let service = StubPullRequestsService()
        let authored = makePullRequestSummary(number: 1, isAuthored: true)
        service.listResult = .success(PullRequestListResult(
            summaries: [authored, makePullRequestSummary(number: 2, isReviewRequested: true)],
            warnings: []
        ))
        let notificationCenter = NotificationCenter()
        let viewModel = makePullRequestsViewModel(service: service, notificationCenter: notificationCenter)
        // The default All tab warms every bucket, so the switch to Authored issues nothing.
        await viewModel.refreshForScreen()
        viewModel.selectFilter(.authored)
        XCTAssertEqual(service.listRequests.count, 1)

        // An agent mutation announces itself; the visible tab reloads unconditionally...
        notificationCenter.post(
            name: .pullRequestChangedOnGitHub,
            object: nil,
            userInfo: [
                PullRequestChangeNotificationKey.announcement: PullRequestChangeAnnouncement(
                    identifier: authored.id,
                    affectsListRow: true
                )
            ]
        )
        await waitFor { service.listRequests.count == 2 }
        XCTAssertEqual(service.listRequests.last?.buckets, [.authored])

        // ...and the buckets it does not render went stale, so the next tab refetches rather
        // than trusting a freshness window that predates the mutation.
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.listRequests.count, 3)
        XCTAssertEqual(service.listRequests.last?.buckets, [.reviewRequested, .reviewed])
    }

    func testAFailedBucketLeavesATabRenderingItsHealthyOne() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            warnings: []
        ))
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.selectFilter(.authored)
        await viewModel.refreshForScreen()

        service.listResult = .failure(.rateLimited)
        viewModel.selectFilter(.all)
        await viewModel.loadIfNeeded(for: .all)

        // The All tab keeps the authored rows and explains the failure over them.
        XCTAssertEqual(viewModel.loadPhase(for: .all), .loaded)
        XCTAssertEqual(viewModel.items.map(\.id.number), [1])
        XCTAssertNotNil(viewModel.errorMessage)
        // Reviewing has nothing that loaded, so it is unavailable rather than emptily "loaded".
        XCTAssertEqual(
            viewModel.loadPhase(for: .reviewing),
            .unavailable(PullRequestsUnavailableReason(.rateLimited))
        )
    }
}
