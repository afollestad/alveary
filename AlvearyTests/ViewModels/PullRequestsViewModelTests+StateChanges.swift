import Foundation
import XCTest

@testable import Alveary

/// State changes to the pull request itself — close, reopen, leaving draft: the
/// status applies to the pane and its list row right away, then the detail
/// refetches so GitHub's own timeline row lands in the Overview.
@MainActor
extension PullRequestsViewModelTests {
    private func openedPane(
        status: PullRequestStatus,
        refetchedStatus: PullRequestStatus? = nil,
        nodeID: String? = "PR_7",
        setClosedResult: Result<Void, PullRequestsServiceError> = .success(()),
        readyForReviewResult: Result<Void, PullRequestsServiceError> = .success(())
    ) async -> OpenedStatePane {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, status: status)
        service.detailResult = .success(
            makePullRequestDetail(id: summary.id, status: status, viewerCanUpdate: true, nodeID: nodeID)
        )
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.setClosedResult = setClosedResult
        service.readyForReviewResult = readyForReviewResult
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        if let refetchedStatus {
            service.detailResult = .success(
                makePullRequestDetail(id: summary.id, status: refetchedStatus, viewerCanUpdate: true)
            )
        }
        return OpenedStatePane(viewModel: viewModel, service: service, id: summary.id)
    }

    func testCloseAppliesStatusToPaneAndRowThenRefetches() async {
        let pane = await openedPane(status: .open, refetchedStatus: .closed)
        let detailCallsBefore = pane.service.detailCallCount

        pane.viewModel.setPullRequestClosed(true)
        await pane.waitForStateChange()

        XCTAssertEqual(pane.service.stateChanges, [true])
        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .closed)
        XCTAssertEqual(pane.viewModel.activePaneSession?.detail?.status, .closed)
        XCTAssertEqual(pane.listedStatus, .closed)
        // The refetch is what brings the closed timeline row into the Overview.
        XCTAssertEqual(pane.service.detailCallCount, detailCallsBefore + 1)
        XCTAssertNil(pane.viewModel.activePaneSession?.stateChangeError)
    }

    func testReopenSendsOpenAndTakesTheRefetchedDraftStatus() async {
        // A reopened draft comes back as `.draft`, correcting the optimistic `.open`.
        let pane = await openedPane(status: .closed, refetchedStatus: .draft)

        pane.viewModel.setPullRequestClosed(false)
        await pane.waitForStateChange()

        XCTAssertEqual(pane.service.stateChanges, [false])
        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .draft)
        XCTAssertEqual(pane.listedStatus, .draft)
    }

    func testStateChangeFailureKeepsStatusAndSurfacesError() async {
        let pane = await openedPane(
            status: .open,
            setClosedResult: .failure(.requestFailed(statusCode: 422))
        )
        let detailCallsBefore = pane.service.detailCallCount

        pane.viewModel.setPullRequestClosed(true)
        await pane.waitForStateChange()

        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .open)
        XCTAssertEqual(pane.listedStatus, .open)
        XCTAssertEqual(pane.service.detailCallCount, detailCallsBefore)
        XCTAssertEqual(
            pane.viewModel.activePaneSession?.stateChangeError,
            PullRequestsServiceError.requestFailed(statusCode: 422).localizedDescription
        )

        pane.viewModel.clearPullRequestStateChangeError()
        XCTAssertNil(pane.viewModel.activePaneSession?.stateChangeError)
    }

    func testMarkReadyForReviewSendsNodeIDAndTakesTheRefetchedStatus() async {
        let pane = await openedPane(status: .draft, refetchedStatus: .open)
        let detailCallsBefore = pane.service.detailCallCount

        pane.viewModel.markPullRequestReadyForReview()
        await pane.waitForStateChange()

        XCTAssertEqual(pane.service.readyForReviewNodeIDs, ["PR_7"])
        XCTAssertEqual(pane.service.stateChanges, [])
        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .open)
        XCTAssertEqual(pane.listedStatus, .open)
        // The refetch is what brings the ready-for-review timeline row in.
        XCTAssertEqual(pane.service.detailCallCount, detailCallsBefore + 1)
        XCTAssertNil(pane.viewModel.activePaneSession?.stateChangeError)
    }

    func testMarkReadyForReviewFailureKeepsDraftAndSurfacesError() async {
        let pane = await openedPane(
            status: .draft,
            readyForReviewResult: .failure(.requestFailed(statusCode: 404))
        )
        let detailCallsBefore = pane.service.detailCallCount

        pane.viewModel.markPullRequestReadyForReview()
        await pane.waitForStateChange()

        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .draft)
        XCTAssertEqual(pane.listedStatus, .draft)
        XCTAssertEqual(pane.service.detailCallCount, detailCallsBefore)
        XCTAssertEqual(
            pane.viewModel.activePaneSession?.stateChangeError,
            PullRequestsServiceError.requestFailed(statusCode: 404).localizedDescription
        )
    }

    func testMarkReadyForReviewWithoutNodeIDDoesNothing() async {
        // No node id means no mutation to address — the optimistic status must
        // not move either.
        let pane = await openedPane(status: .draft, nodeID: nil)

        pane.viewModel.markPullRequestReadyForReview()
        for _ in 0..<50 {
            await Task.yield()
        }

        XCTAssertEqual(pane.mutationCount, 0)
        XCTAssertEqual(pane.viewModel.activePaneSession?.summary.status, .draft)
        XCTAssertEqual(pane.listedStatus, .draft)
        XCTAssertEqual(pane.viewModel.activePaneSession?.isChangingState, false)
    }

    func testStateChangeIgnoresReentryWhileInFlight() async {
        let pane = await openedPane(status: .open, refetchedStatus: .closed)
        let gate = PullRequestsServiceGate()
        pane.service.detailGate = gate

        pane.viewModel.setPullRequestClosed(true)
        for _ in 0..<2_000 where pane.service.stateChanges.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(pane.viewModel.activePaneSession?.isChangingState, true)

        // The button is disabled meanwhile; a stray call must not double-fire.
        pane.viewModel.setPullRequestClosed(true)
        gate.open()
        await pane.waitForStateChange()

        XCTAssertEqual(pane.service.stateChanges, [true])
    }
}

@MainActor
private struct OpenedStatePane {
    let viewModel: PullRequestsViewModel
    let service: StubPullRequestsService
    let id: PullRequestIdentifier

    var listedStatus: PullRequestStatus? {
        viewModel.items.first { $0.id == id }?.status
    }

    /// Every state mutation the stub has seen, whichever endpoint it used.
    var mutationCount: Int {
        service.stateChanges.count + service.readyForReviewNodeIDs.count
    }

    /// Settles once the mutation has been sent and the round trip has finished.
    func waitForStateChange() async {
        for _ in 0..<2_000 where mutationCount == 0
            || viewModel.activePaneSession?.isChangingState == true {
            await Task.yield()
        }
    }
}
