import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testRequestDetailsActivatesSessionAndLoadsContent() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 2))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertTrue(viewModel.isDetailActive(summary.id))
        XCTAssertEqual(viewModel.paneSessions[target]?.summary?.id, summary.id)

        await waitForPaneContent(viewModel, target: target)
        XCTAssertEqual(viewModel.paneSessions[target]?.detail?.title, "Detail title")
        XCTAssertEqual(viewModel.paneSessions[target]?.diffState, .loaded)
        XCTAssertEqual(viewModel.paneSessions[target]?.diffFiles?.count, 2)
    }

    func testRequestDetailsReusesCachedSession() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        viewModel.deactivatePane()
        viewModel.requestDetails(summary)

        XCTAssertEqual(service.detailCallCount, 1)
        XCTAssertEqual(service.diffCallCount, 1)
        XCTAssertEqual(viewModel.activePaneTarget, target)
    }

    func testStaleLoadCompletionCannotResurrectDismissedSession() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        let detailGate = PullRequestsServiceGate()
        let diffGate = PullRequestsServiceGate()
        service.detailGate = detailGate
        service.diffGate = diffGate
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        guard let generation = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Expected a live session")
        }
        viewModel.dismissPane(target, generation: generation)
        XCTAssertNil(viewModel.paneSessions[target])

        detailGate.open()
        diffGate.open()
        await drainMainQueue()

        XCTAssertNil(viewModel.paneSessions[target])
        XCTAssertNil(viewModel.activePaneTarget)
    }

    func testDeactivateThenDismissLifecycle() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        guard let generation = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Expected a live session")
        }

        // Route-only deactivation preserves the session.
        viewModel.deactivatePane()
        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertNotNil(viewModel.paneSessions[target])

        // Close flow: deactivate with generation, then dismiss discards the session.
        viewModel.requestDetails(summary)
        viewModel.deactivatePane(target, generation: generation)
        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(.init(target: target, generation: generation)))

        viewModel.dismissPane(target, generation: generation)
        XCTAssertNil(viewModel.paneSessions[target])
        XCTAssertTrue(viewModel.pendingPaneDismissals.isEmpty)
    }

    func testDeactivateWithStaleGenerationIsIgnored() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        viewModel.deactivatePane(target, generation: UUID())

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertTrue(viewModel.pendingPaneDismissals.isEmpty)
    }

    func testReopeningPendingDismissalStartsFreshSession() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)
        guard let firstGeneration = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Expected a live session")
        }
        viewModel.deactivatePane(target, generation: firstGeneration)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertNotEqual(viewModel.paneSessions[target]?.generation, firstGeneration)
        XCTAssertTrue(viewModel.pendingPaneDismissals.isEmpty)
        XCTAssertEqual(service.detailCallCount, 2)
    }

    func testDiffTooLargeAndFailureStates() async {
        for (result, expected) in [
            (Result<String, PullRequestsServiceError>.failure(.responseTooLarge), PullRequestDiffState.tooLarge),
            (.failure(.transport("boom")), .failed("boom"))
        ] {
            let service = StubPullRequestsService()
            let summary = makePullRequestSummary(number: 7)
            service.detailResult = .success(makePullRequestDetail(id: summary.id))
            service.diffResult = result
            let viewModel = makePullRequestsViewModel(service: service)
            let target = PullRequestPaneTarget.details(summary.id)

            viewModel.requestDetails(summary)
            await waitForPaneContent(viewModel, target: target)

            XCTAssertEqual(viewModel.paneSessions[target]?.diffState, expected)
        }
    }

    func testShowMoreDiffFilesGrowsPrefixWindow() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 20))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)

        XCTAssertEqual(
            viewModel.paneSessions[target]?.renderedDiffFileCount,
            PullRequestDiffFilePaging.initialFileCount
        )
        viewModel.showMoreDiffFiles()
        XCTAssertEqual(viewModel.paneSessions[target]?.renderedDiffFileCount, 20)
    }

    func testDiffLoadSeedsAutoCollapseAndToggleFlips() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        // One oversized file (collapses) followed by a small one (stays expanded).
        service.diffResult = .success(
            makeUnifiedDiffFixture(fileCount: 1, addedLinesPerFile: 401)
                + makeUnifiedDiffFixture(fileCount: 1)
        )
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: target)

        let collapsed = viewModel.paneSessions[target]?.collapsedDiffFileIDs ?? []
        XCTAssertEqual(collapsed.count, 1)
        guard let collapsedID = collapsed.first else {
            return XCTFail("Expected one auto-collapsed file")
        }

        viewModel.toggleDiffFileCollapse(collapsedID)
        XCTAssertEqual(viewModel.paneSessions[target]?.collapsedDiffFileIDs, [])
        viewModel.toggleDiffFileCollapse(collapsedID)
        XCTAssertEqual(viewModel.paneSessions[target]?.collapsedDiffFileIDs, [collapsedID])
    }
}

@MainActor
extension PullRequestsViewModelTests {
    func testSelectAdjacentRowStepsAndClamps() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        let rows = [
            makePullRequestSummary(number: 1),
            makePullRequestSummary(number: 2),
            makePullRequestSummary(number: 3)
        ]

        XCTAssertNil(viewModel.selectAdjacentRow(in: [], forward: true))

        // No selection: Down selects the first row, Up the last.
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: true)?.number, 1)
        viewModel.deactivatePane()
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: false)?.number, 3)

        // Up steps back through the list and clamps at the first row.
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: false)?.number, 2)
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: false)?.number, 1)
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: false)?.number, 1)

        // Down steps forward and clamps at the last row.
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: true)?.number, 2)
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: true)?.number, 3)
        XCTAssertEqual(viewModel.selectAdjacentRow(in: rows, forward: true)?.number, 3)
        XCTAssertTrue(viewModel.isDetailActive(rows[2].id))
    }

    // MARK: - Opening from an identifier alone

    /// A transcript's unlink card names a pull request no snapshot covers, so the pane has to
    /// open on the click's own cycle and load its own detail rather than waiting on a fetch.
    func testRequestDetailsByIdentifierOpensPaneBeforeTheDetailLoads() async {
        let service = StubPullRequestsService()
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        let detailGate = PullRequestsServiceGate()
        service.detailGate = detailGate
        service.detailResult = .success(makePullRequestDetail(id: identifier))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(identifier)

        viewModel.requestDetails(identifier, origin: .screen)

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertNil(viewModel.paneSessions[target]?.summary)
        XCTAssertEqual(viewModel.paneSessions[target]?.isLoadingDetail, true)

        detailGate.open()
        await waitForPaneContent(viewModel, target: target)
    }

    /// The detail is what a summary would have been derived from, so it backfills one — which is
    /// what restores the footer's authorship gate and the toolbar's status glyph.
    func testIdentifierOpenedPaneBackfillsItsSummaryFromTheDetail() async {
        let service = StubPullRequestsService()
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        var detail = makePullRequestDetail(id: identifier, title: "Add caching", status: .draft)
        detail.viewerLogin = "alice"
        service.detailResult = .success(detail)
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(identifier)

        viewModel.requestDetails(identifier, origin: .screen)
        await waitForPaneContent(viewModel, target: target)

        let summary = viewModel.paneSessions[target]?.summary
        XCTAssertEqual(summary?.id, identifier)
        XCTAssertEqual(summary?.title, "Add caching")
        XCTAssertEqual(summary?.status, .draft)
        // The fixture's author is `alice`, so a matching viewer is the authored case.
        XCTAssertEqual(summary?.isAuthored, true)
    }

    /// The failure renders in the pane's own banner now, so nothing may be toasted and the pane
    /// stays open with no summary to show.
    func testIdentifierOpenedPaneSurfacesDetailFailureInTheSession() async {
        let service = StubPullRequestsService()
        let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
        service.detailResult = .failure(.transport("no network"))
        service.diffResult = .failure(.transport("no network"))
        var toasts: [String] = []
        let viewModel = makePullRequestsViewModel(service: service, presentToast: { toasts.append($0) })
        let target = PullRequestPaneTarget.details(identifier)

        viewModel.requestDetails(identifier, origin: .screen)
        await waitForPaneContent(viewModel, target: target)

        XCTAssertEqual(viewModel.activePaneTarget, target)
        XCTAssertNotNil(viewModel.paneSessions[target]?.detailError)
        XCTAssertNil(viewModel.paneSessions[target]?.summary)
        XCTAssertTrue(toasts.isEmpty)
    }

    /// A listed row already carries a usable snapshot, so the pane opens with a populated header
    /// and still pays exactly one detail fetch — the pane's own.
    func testRequestDetailsByIdentifierReusesAListedRow() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7, title: "Listed title")
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(service: service)
        let target = PullRequestPaneTarget.details(summary.id)
        await viewModel.refresh()

        viewModel.requestDetails(summary.id, origin: .screen)

        XCTAssertEqual(viewModel.paneSessions[target]?.summary?.title, "Listed title")
        await waitForPaneContent(viewModel, target: target)
        XCTAssertEqual(service.detailCallCount, 1)
    }
}
