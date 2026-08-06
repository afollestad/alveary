import XCTest

@testable import Alveary

// Cancellation, restart, and retry for a pane's detail and diff loads —
// the behaviour owned by `PullRequestsViewModel+PaneLoading.swift`.
@MainActor
extension PullRequestsViewModelTests {
    // MARK: - Superseded load cancellation

    func testOpeningAnotherPaneCancelsTheSupersededLoad() async {
        let service = StubPullRequestsService()
        let first = makePullRequestSummary(number: 7)
        let second = makePullRequestSummary(number: 8)
        let detailGate = PullRequestsServiceGate()
        service.detailGate = detailGate
        service.diffGate = PullRequestsServiceGate()
        service.detailResult = .success(makePullRequestDetail(id: first.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let firstTarget = PullRequestPaneTarget.details(first.id)

        viewModel.requestDetails(first)
        await drainMainQueue()
        viewModel.requestDetails(second)
        await drainMainQueue()

        // Releasing the gate lets the superseded call unwind; it must leave no trace.
        detailGate.open()
        await drainMainQueue()

        XCTAssertNil(viewModel.paneLoadTasks[firstTarget])
        XCTAssertNil(viewModel.paneSessions[firstTarget]?.detail)
        // Cancellation is not a failure: the session stays detectably incomplete so
        // reopening restarts it, rather than showing a banner nobody asked for.
        XCTAssertNil(viewModel.paneSessions[firstTarget]?.detailError)
        XCTAssertEqual(viewModel.paneSessions[firstTarget]?.diffState, .loading)
    }

    /// The held-arrow path through `selectAdjacentRow`: every row it passes over
    /// opens a pane, and only the one it lands on may keep loading.
    func testWalkingSeveralRowsLeavesOnlyTheLastLoading() async {
        let service = StubPullRequestsService()
        let rows = (7...9).map { makePullRequestSummary(number: $0) }
        service.detailGate = PullRequestsServiceGate()
        service.diffGate = PullRequestsServiceGate()
        service.detailResult = .success(makePullRequestDetail(id: rows[2].id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)

        for row in rows {
            viewModel.requestDetails(row)
        }

        XCTAssertEqual(viewModel.paneLoadTasks.count, 1)
        XCTAssertNotNil(viewModel.paneLoadTasks[.details(rows[2].id)])
        XCTAssertNil(viewModel.paneLoadTasks[.details(rows[0].id)])
        XCTAssertNil(viewModel.paneLoadTasks[.details(rows[1].id)])
    }

    func testReopeningACancelledPaneStartsAFreshLoad() async {
        let service = StubPullRequestsService()
        let first = makePullRequestSummary(number: 7)
        let second = makePullRequestSummary(number: 8)
        let detailGate = PullRequestsServiceGate()
        service.detailGate = detailGate
        service.diffGate = PullRequestsServiceGate()
        service.detailResult = .success(makePullRequestDetail(id: first.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let firstTarget = PullRequestPaneTarget.details(first.id)

        viewModel.requestDetails(first)
        await drainMainQueue()
        viewModel.requestDetails(second)
        await drainMainQueue()
        detailGate.open()
        await drainMainQueue()

        // Coming back to a pane whose load was cancelled must not sit on the spinner.
        service.detailGate = nil
        service.diffGate = nil
        viewModel.requestDetails(first)
        await waitForPaneContent(viewModel, target: firstTarget)

        XCTAssertNotNil(viewModel.paneSessions[firstTarget]?.detail)
        XCTAssertEqual(service.detailCallCount, 3)
    }

    func testDismissCancelsInFlightLoads() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailGate = PullRequestsServiceGate()
        service.diffGate = PullRequestsServiceGate()
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        guard let generation = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Expected a live session")
        }
        XCTAssertNotNil(viewModel.paneLoadTasks[target])

        viewModel.dismissPane(target, generation: generation)

        XCTAssertNil(viewModel.paneLoadTasks[target])
    }

    // MARK: - Retry after failure

    func testRetryDetailLoadClearsTheErrorAndRefetches() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .failure(.transport("gh timed out after 30 seconds"))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        XCTAssertNotNil(viewModel.paneSessions[target]?.detailError)

        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        viewModel.retryDetailLoad()

        // The banner gives way to the spinner while the retry runs.
        XCTAssertNil(viewModel.paneSessions[target]?.detailError)
        XCTAssertEqual(viewModel.paneSessions[target]?.isLoadingDetail, true)

        await waitForPaneContent(viewModel, target: target)
        XCTAssertEqual(viewModel.paneSessions[target]?.detail?.title, "Detail title")
        XCTAssertEqual(service.detailCallCount, 2)
    }

    /// A reopen must not silently refetch a pull request that reliably fails; only
    /// the explicit Retry may, which is why `resumeIncompleteLoads` skips failures.
    func testReopeningAFailedPaneDoesNotRefetch() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        let other = makePullRequestSummary(number: 8)
        service.detailResult = .failure(.transport("boom"))
        service.diffResult = .failure(.transport("boom"))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        let callsAfterFirstOpen = service.detailCallCount

        viewModel.requestDetails(other)
        viewModel.requestDetails(summary)
        await drainMainQueue()

        XCTAssertEqual(service.detailCallCount, callsAfterFirstOpen + 1)
        XCTAssertNotNil(viewModel.paneSessions[target]?.detailError)
    }

    func testRetryDiffLoadRefetchesAndTooLargeDoesNot() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .failure(.transport("gh timed out after 60 seconds"))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        XCTAssertEqual(viewModel.paneSessions[target]?.diffState, .failed("gh timed out after 60 seconds"))

        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))
        viewModel.retryDiffLoad()
        await waitForPaneContent(viewModel, target: target)

        XCTAssertEqual(viewModel.paneSessions[target]?.diffState, .loaded)
        XCTAssertEqual(viewModel.paneSessions[target]?.diffFiles?.count, 2)
        XCTAssertEqual(service.diffCallCount, 2)

        // An over-cap response is deterministic, so retrying cannot help and the
        // Changes tab offers no button for it.
        viewModel.mutateActiveSession { $0.diffState = .tooLarge }
        viewModel.retryDiffLoad()
        await drainMainQueue()

        XCTAssertEqual(viewModel.paneSessions[target]?.diffState, .tooLarge)
        XCTAssertEqual(service.diffCallCount, 2)
    }

    /// Retrying a load that has not failed is a no-op — the banner is the only way
    /// in, but the method guards itself rather than trusting its one caller.
    func testRetryIsIgnoredWhileTheFirstLoadIsStillRunning() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailGate = PullRequestsServiceGate()
        service.diffGate = PullRequestsServiceGate()
        let viewModel = makePullRequestsViewModel(service: service)

        viewModel.requestDetails(summary)
        await drainMainQueue()
        XCTAssertEqual(service.detailCallCount, 1)

        viewModel.retryDetailLoad()
        await drainMainQueue()

        XCTAssertEqual(service.detailCallCount, 1)
    }

    /// The live-task guard is reachable despite the error guard above it: the
    /// mutation refetches call `loadDetail` directly, outside `paneLoadTasks`, so one
    /// of them failing can set `detailError` while a retry is still in flight. Without
    /// the guard that combination would start a second concurrent fetch.
    func testRetryIsIgnoredWhileAnEarlierRetryIsStillRunning() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .failure(.transport("boom"))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        XCTAssertEqual(service.detailCallCount, 1)

        // Park the retry in flight, then stand in for a concurrent mutation refetch
        // landing its own failure on the same session.
        service.detailGate = PullRequestsServiceGate()
        viewModel.retryDetailLoad()
        await drainMainQueue()
        XCTAssertEqual(service.detailCallCount, 2)
        viewModel.mutateActiveSession { $0.detailError = "a refetch failed meanwhile" }

        viewModel.retryDetailLoad()
        await drainMainQueue()

        XCTAssertEqual(service.detailCallCount, 2)
    }

    /// A cancelled load and its replacement share a generation, so only the token
    /// keeps the loser's completion from clearing the winner's handle.
    func testARestartedLoadIsNotClobberedByTheTaskItReplaced() async {
        let service = StubPullRequestsService()
        let first = makePullRequestSummary(number: 7)
        let second = makePullRequestSummary(number: 8)
        let firstGate = PullRequestsServiceGate()
        let secondGate = PullRequestsServiceGate()
        service.detailGate = firstGate
        service.diffGate = PullRequestsServiceGate()
        service.detailResult = .success(makePullRequestDetail(id: first.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let firstTarget = PullRequestPaneTarget.details(first.id)

        viewModel.requestDetails(first)
        await drainMainQueue()
        viewModel.requestDetails(second)
        await drainMainQueue()

        // The replacement parks on its own gate, so the doomed load can unwind alone.
        service.detailGate = secondGate
        viewModel.requestDetails(first)
        await drainMainQueue()
        XCTAssertEqual(service.detailCallCount, 3)

        // Both cancelled loads now run their completion cleanup while the
        // replacement is still parked on `secondGate`.
        firstGate.open()
        await drainMainQueue()

        // The replacement is still in flight, so reopening must not start a fourth.
        viewModel.requestDetails(first)
        await drainMainQueue()
        XCTAssertEqual(service.detailCallCount, 3)

        secondGate.open()
        await drainMainQueue()
        XCTAssertNotNil(viewModel.paneSessions[firstTarget]?.detail)
    }
}
