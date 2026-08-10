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

        // Switching tabs fetches the two buckets the first tab never paid for, not all three —
        // one request each, since a tab's buckets go out concurrently.
        let afterAuthored = service.listRequests.count
        viewModel.selectFilter(.all)
        await viewModel.loadIfNeeded(for: .all)

        XCTAssertEqual(service.listRequests.count, afterAuthored + 2)
        XCTAssertEqual(service.bucketsRequested(since: afterAuthored), [.reviewRequested, .reviewed])
        XCTAssertEqual(viewModel.items.map(\.id.number).sorted(), [1, 2, 3])

        // Every bucket the Reviewing tab needs is already warm, so it issues nothing.
        let afterAll = service.listRequests.count
        viewModel.selectFilter(.reviewing)
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.listRequests.count, afterAll)
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

        let afterOpen = service.listRequests.count
        viewModel.selectStatusFilter(.merged)
        await waitFor { service.listRequests.count == afterOpen + 1 }

        // The visible tab reloads under the new status; the buckets it does not render wait.
        XCTAssertEqual(service.listRequests.last?.status, .merged)
        XCTAssertEqual(service.bucketsRequested(since: afterOpen), [.authored])

        // The other tabs' buckets were marked stale, so visiting one refetches it.
        let afterMerged = service.listRequests.count
        viewModel.selectFilter(.reviewing)
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.bucketsRequested(since: afterMerged), [.reviewRequested, .reviewed])
        XCTAssertTrue(service.listRequests.dropFirst(afterMerged).allSatisfy { $0.status == .merged })
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
        let afterWarm = service.listRequests.count
        XCTAssertEqual(afterWarm, PullRequestsFilter.all.requiredBuckets.count)

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
        await waitFor { service.listRequests.count == afterWarm + 1 }
        XCTAssertEqual(service.bucketsRequested(since: afterWarm), [.authored])

        // ...and the buckets it does not render went stale, so the next tab refetches rather
        // than trusting a freshness window that predates the mutation.
        let afterReload = service.listRequests.count
        await viewModel.loadIfNeeded(for: .reviewing)
        XCTAssertEqual(service.listRequests.count, afterReload + 2)
        XCTAssertEqual(service.bucketsRequested(since: afterReload), [.reviewRequested, .reviewed])
    }

    func testATabsBucketsGoOutConcurrentlyAndLandOnOneBarrier() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [
                makePullRequestSummary(number: 1, isAuthored: true),
                makePullRequestSummary(number: 2, isReviewRequested: true),
                makePullRequestSummary(number: 3, hasReviewed: true)
            ],
            warnings: []
        ))
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        let viewModel = makePullRequestsViewModel(service: service)
        let expected = PullRequestsFilter.all.requiredBuckets

        let refreshTask = Task { await viewModel.refresh() }
        // The stub records each request before waiting on the gate, so every leg reaching it
        // while the gate is shut is what proves they are in flight together rather than queued.
        await waitFor { service.listRequests.count == expected.count }
        XCTAssertEqual(service.bucketsRequested(since: 0), expected)
        // ...and none of them has published: the barrier is what keeps a tab settling once.
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.loadPhase, .loading)

        gate.open()
        await refreshTask.value

        XCTAssertEqual(viewModel.items.map(\.id.number).sorted(), [1, 2, 3])
        XCTAssertEqual(viewModel.loadPhase, .loaded)
    }

    func testAFailedLegLeavesItsHealthySiblingsRendered() async {
        let service = StubPullRequestsService()
        service.listResultsByBucket = [
            .authored: .success(PullRequestListResult(
                summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
                warnings: []
            )),
            .reviewRequested: .failure(.rateLimited),
            .reviewed: .success(PullRequestListResult(
                summaries: [makePullRequestSummary(number: 3, hasReviewed: true)],
                warnings: []
            ))
        ]
        let viewModel = makePullRequestsViewModel(service: service)

        await viewModel.refresh()

        // One leg failing must not cost the legs that succeeded — the batched request could only
        // fail all of them together.
        XCTAssertEqual(viewModel.items.map(\.id.number).sorted(), [1, 3])
        XCTAssertEqual(viewModel.loadPhase(for: .all), .loaded)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.bucketFailures[.reviewRequested], .rateLimited)
        XCTAssertNil(viewModel.bucketFailures[.authored])
        XCTAssertNil(viewModel.bucketFailures[.reviewed])
    }

    func testEveryLegRepeatingAWarningShowsItOnce() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            // SAML answers every bucket with the same message.
            warnings: ["Resource protected by organization SAML enforcement."]
        ))
        let viewModel = makePullRequestsViewModel(service: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.warnings, ["Resource protected by organization SAML enforcement."])
    }

    func testACancelledLoadDropsEvenTheLegsThatSucceeded() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, isAuthored: true)],
            warnings: []
        ))
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        let viewModel = makePullRequestsViewModel(service: service)

        let refreshTask = Task { await viewModel.refresh() }
        await waitFor { service.listRequests.count == PullRequestsFilter.all.requiredBuckets.count }
        refreshTask.cancel()
        gate.open()
        await refreshTask.value

        // Applying the legs that landed would stamp a half-loaded tab `fetchedAt: now`, and the
        // freshness throttle would then suppress the load that should have completed it.
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertEqual(viewModel.loadPhase, .idle)
        XCTAssertTrue(viewModel.bucketStates.isEmpty)

        // So the next load genuinely refetches rather than reading the buckets as warm.
        let afterCancel = service.listRequests.count
        await viewModel.loadIfNeeded(for: .all)
        XCTAssertEqual(service.bucketsRequested(since: afterCancel), PullRequestsFilter.all.requiredBuckets)
    }

    func testALoadFinishingAfterAStatusChangeDiscardsItselfAndRedrives() async {
        let service = StubPullRequestsService()
        service.listResult = .success(PullRequestListResult(
            summaries: [makePullRequestSummary(number: 1, status: .merged, isAuthored: true)],
            warnings: []
        ))
        let gate = PullRequestsServiceGate()
        service.listGate = gate
        // The tab comes from persistence rather than `selectFilter`, whose spawned load would own
        // the gated leg below and leave `refreshTask` with nothing to await.
        let settings = InMemorySettingsService()
        settings.update { $0.pullRequestsSelectedTab = "Authored" }
        let viewModel = makePullRequestsViewModel(service: service, settingsService: settings)

        let refreshTask = Task { await viewModel.refresh() }
        await waitFor { service.listRequests.count == 1 }
        // The selection moves while the leg is held open. `selectStatusFilter`'s own reload skips
        // the in-flight bucket, so the barrier's hand-off is the only thing that refetches it.
        viewModel.selectStatusFilter(.merged)
        gate.open()
        await refreshTask.value

        // The stale leg discarded its rows and re-drove one fetch under the new status.
        XCTAssertEqual(service.listRequests.map(\.status), [.open, .merged])
        XCTAssertEqual(viewModel.items.map(\.id.number), [1])
        XCTAssertEqual(viewModel.loadPhase, .loaded)
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
