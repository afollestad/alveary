import XCTest

@testable import Alveary

/// Row inputs that must stay equal across render passes. Every visible row carries
/// `referenceDate`, and its highlight comes from `activeDetailIdentifier`, so a value
/// that changes on every read would make each row rebuild on every pass — which is what
/// kept a click's selection from painting until the whole list had re-rendered.
@MainActor
extension PullRequestsViewModelTests {
    func testReferenceDateIsStableAcrossReadsWhileTheClockRuns() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            now: {
                currentDate = currentDate.addingTimeInterval(1)
                return currentDate
            }
        )

        XCTAssertEqual(viewModel.referenceDate, viewModel.referenceDate)
    }

    func testTouchReferenceDateAdvancesTheStoredValue() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            now: { currentDate }
        )
        let initial = viewModel.referenceDate

        currentDate = currentDate.addingTimeInterval(120)
        viewModel.touchReferenceDate()

        XCTAssertEqual(viewModel.referenceDate, currentDate)
        XCTAssertNotEqual(viewModel.referenceDate, initial)
    }

    /// Snapshot hosts inject a fixed clock; the equality guard is what keeps a tick from
    /// publishing a no-op change into their render.
    func testTouchReferenceDateIsInertUnderAFixedClock() {
        let fixed = Date(timeIntervalSince1970: 1_000)
        let viewModel = makePullRequestsViewModel(
            service: StubPullRequestsService(),
            now: { fixed }
        )

        viewModel.touchReferenceDate()

        XCTAssertEqual(viewModel.referenceDate, fixed)
    }

    func testRefreshAdvancesTheReferenceDate() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service, now: { currentDate })

        currentDate = currentDate.addingTimeInterval(600)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.referenceDate, currentDate)
    }

    /// The row's `==` is what lets `.equatable()` skip unchanged rows; a fresh `onSelect`
    /// closure every pass must not defeat it, while every rendered input must.
    func testPullRequestRowEqualityIgnoresTheActionAndComparesRenderedInputs() {
        let loader = GitHubAvatarLoader()
        let date = Date(timeIntervalSince1970: 1_000)
        func makeRow(
            isSelected: Bool = false,
            referenceDate: Date = date,
            onSelect: @escaping () -> Void = {}
        ) -> PullRequestRow {
            PullRequestRow(
                summary: makePullRequestSummary(number: 1),
                showsRepository: true,
                isSelected: isSelected,
                referenceDate: referenceDate,
                avatarLoader: loader,
                onSelect: onSelect
            )
        }

        XCTAssertEqual(makeRow(onSelect: {}), makeRow(onSelect: { _ = loader }))
        XCTAssertNotEqual(makeRow(), makeRow(isSelected: true))
        XCTAssertNotEqual(makeRow(), makeRow(referenceDate: date.addingTimeInterval(60)))
    }

    /// The sectioned list skips rebuilding its rows during the right pane's slide-in, so
    /// its `==` must ignore the action while tracking everything the rows render.
    func testSectionedListEqualityIgnoresTheActionAndComparesRenderedInputs() {
        let loader = GitHubAvatarLoader()
        let date = Date(timeIntervalSince1970: 1_000)
        let sections = [
            PullRequestListSection(id: "all", title: nil, rows: [makePullRequestSummary(number: 1)])
        ]
        func makeList(
            sections: [PullRequestListSection] = sections,
            activeDetailID: PullRequestIdentifier? = nil,
            onSelect: @escaping (PullRequestSummary) -> Void = { _ in }
        ) -> PullRequestsSectionedList {
            PullRequestsSectionedList(
                sections: sections,
                showsRepository: true,
                referenceDate: date,
                avatarLoader: loader,
                activeDetailID: activeDetailID,
                onSelect: onSelect
            )
        }

        XCTAssertEqual(makeList(), makeList(onSelect: { _ = $0 }))
        XCTAssertNotEqual(makeList(), makeList(activeDetailID: sections[0].rows[0].id))
        XCTAssertNotEqual(makeList(), makeList(sections: []))
    }

    // MARK: - Pane render boundary

    /// The lane re-runs its body on every resize-drag frame and every pane-session write;
    /// the pane's `==` is what keeps that off the detail subtree.
    func testPullRequestPaneEqualityIgnoresTheDismissActionAndComparesTheTarget() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        let other = makePullRequestsViewModel(service: StubPullRequestsService())
        let target = PullRequestPaneTarget.details(makePullRequestSummary(number: 1).id)
        let otherTarget = PullRequestPaneTarget.details(makePullRequestSummary(number: 2).id)

        XCTAssertEqual(
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: {}),
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: { _ = target })
        )
        XCTAssertNotEqual(
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: {}),
            PullRequestPane(viewModel: viewModel, target: otherTarget, onDismiss: {})
        )
        XCTAssertNotEqual(
            PullRequestPane(viewModel: viewModel, target: target, onDismiss: {}),
            PullRequestPane(viewModel: other, target: target, onDismiss: {})
        )
    }

    /// Each tab and the footer take the session by value, so a write to a *different*
    /// target's session must leave them equal.
    func testPullRequestPaneChildrenCompareTheSessionTheyRender() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        let summary = makePullRequestSummary(number: 1)
        let session = PullRequestPaneSession(generation: UUID(), summary: summary)
        let target = PullRequestPaneTarget.details(summary.id)
        var changed = session
        changed.composerText = "typing"

        XCTAssertEqual(
            PullRequestPaneOverview(session: session, viewModel: viewModel, onOpenFiles: {}),
            PullRequestPaneOverview(session: session, viewModel: viewModel, onOpenFiles: { _ = summary })
        )
        XCTAssertNotEqual(
            PullRequestPaneOverview(session: session, viewModel: viewModel, onOpenFiles: {}),
            PullRequestPaneOverview(session: changed, viewModel: viewModel, onOpenFiles: {})
        )
        XCTAssertEqual(
            PullRequestPaneFiles(session: session, viewModel: viewModel, target: target),
            PullRequestPaneFiles(session: session, viewModel: viewModel, target: target)
        )
        XCTAssertNotEqual(
            PullRequestPaneFiles(session: session, viewModel: viewModel, target: target),
            PullRequestPaneFiles(session: changed, viewModel: viewModel, target: target)
        )
        XCTAssertNotEqual(
            PullRequestPaneReviewFooter(viewModel: viewModel, session: session, target: target),
            PullRequestPaneReviewFooter(viewModel: viewModel, session: changed, target: target)
        )
    }

    func testActiveDetailIdentifierFollowsTheOpenPane() {
        let service = StubPullRequestsService()
        let viewModel = makePullRequestsViewModel(service: service)
        let summary = makePullRequestSummary(number: 7)

        XCTAssertNil(viewModel.activeDetailIdentifier)

        viewModel.requestDetails(summary)
        XCTAssertEqual(viewModel.activeDetailIdentifier, summary.id)
        XCTAssertTrue(viewModel.isDetailActive(summary.id))

        viewModel.deactivatePane()
        XCTAssertNil(viewModel.activeDetailIdentifier)
    }

    // MARK: - Mirrored pane status

    func testActivePaneSummaryStatusFollowsTheOpenPane() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        let summary = makePullRequestSummary(number: 7, status: .open)

        XCTAssertNil(viewModel.activePaneSummaryStatus)

        viewModel.requestDetails(summary)
        XCTAssertEqual(viewModel.activePaneSummaryStatus, .open)

        viewModel.deactivatePane()
        XCTAssertNil(viewModel.activePaneSummaryStatus)
    }

    /// Close, reopen, and mark-ready all apply optimistically through `mutateActiveSession`,
    /// which is what the toolbar glyph follows.
    func testActivePaneSummaryStatusFollowsAnOptimisticSessionWrite() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        viewModel.requestDetails(makePullRequestSummary(number: 7, status: .open))

        viewModel.mutateActiveSession { session in
            session.summary?.status = .merged
        }

        XCTAssertEqual(viewModel.activePaneSummaryStatus, .merged)
    }

    /// The detail load and the state-change refetch both settle the status this way.
    func testActivePaneSummaryStatusFollowsAGenerationGuardedUpdate() throws {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        let summary = makePullRequestSummary(number: 7, status: .open)
        viewModel.requestDetails(summary)
        let target = PullRequestPaneTarget.details(summary.id)
        let generation = try XCTUnwrap(viewModel.paneSessions[target]?.generation)

        viewModel.updateSession(target, generation: generation) { session in
            session.summary?.status = .closed
        }

        XCTAssertEqual(viewModel.activePaneSummaryStatus, .closed)
    }

    /// A session write that cannot change the status must leave the mirror alone —
    /// publishing one anyway would re-render the root for a file collapse.
    func testActivePaneSummaryStatusIgnoresUnrelatedSessionWrites() {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        viewModel.requestDetails(makePullRequestSummary(number: 7, status: .open))

        viewModel.toggleDiffFileCollapse("File0.swift")

        XCTAssertEqual(viewModel.activePaneSummaryStatus, .open)
    }

    func testActivePaneSummaryStatusClearsWhenThePaneIsDismissed() throws {
        let viewModel = makePullRequestsViewModel(service: StubPullRequestsService())
        let summary = makePullRequestSummary(number: 7, status: .open)
        viewModel.requestDetails(summary)
        let target = PullRequestPaneTarget.details(summary.id)
        let generation = try XCTUnwrap(viewModel.paneSessions[target]?.generation)

        viewModel.dismissPane(target, generation: generation)

        XCTAssertNil(viewModel.activePaneSummaryStatus)
    }

    // MARK: - Memoized list shaping

    func testVisibleSectionsRebuildWhenTheirInputsChange() async {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(number: 1, title: "Alpha"),
                    makePullRequestSummary(number: 2, title: "Beta", status: .merged)
                ],
                warnings: []
            )
        )
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).count, 2)

        // Not "Alpha" — the shared `octo/alpha` repository name matches that too.
        viewModel.searchQuery = "Beta"
        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).map(\.title), ["Beta"])

        viewModel.searchQuery = ""
        viewModel.toggleStatusFilter(.merged)
        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).map(\.title), ["Beta"])

        viewModel.toggleStatusFilter(.merged)
        XCTAssertEqual(viewModel.visibleSections(for: .authored).flatMap(\.rows), [])

        service.listResult = .success(
            PullRequestListResult(summaries: [makePullRequestSummary(number: 3, title: "Gamma")], warnings: [])
        )
        await viewModel.refresh()
        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).map(\.title), ["Gamma"])
    }

    /// Without a populated cache every root invalidation would re-run the filter, sort, and
    /// bucket pipeline, and the sectioned list would compare row by row.
    func testVisibleSectionsCacheFillsAndRekeys() async {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(summaries: [makePullRequestSummary(number: 1)], warnings: [])
        )
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()
        viewModel.visibleListCache = nil

        _ = viewModel.visibleSections(for: .all)
        XCTAssertNotNil(viewModel.visibleListCache?.sections)
        XCTAssertEqual(viewModel.visibleListCache?.key.tab, .all)

        viewModel.searchQuery = "nothing matches"
        _ = viewModel.visibleSections(for: .all)
        XCTAssertEqual(viewModel.visibleListCache?.key.searchQuery, "nothing matches")
        XCTAssertEqual(viewModel.visibleListCache?.sections, [])
    }
}
