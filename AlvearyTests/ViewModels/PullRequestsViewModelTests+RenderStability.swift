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
                model: PullRequestRowModel(
                    summary: makePullRequestSummary(number: 1),
                    showsRepository: true,
                    referenceDate: referenceDate
                ),
                isSelected: isSelected,
                avatarLoader: loader,
                onSelect: onSelect
            )
        }

        XCTAssertEqual(makeRow(onSelect: {}), makeRow(onSelect: { _ = loader }))
        XCTAssertNotEqual(makeRow(), makeRow(isSelected: true))
        // A day on, so the rendered age moves; see the same-age case below.
        XCTAssertNotEqual(makeRow(), makeRow(referenceDate: date.addingTimeInterval(86_400)))
    }

    /// `referenceDate` reaches the row only as the age string it produces, so the minute tick
    /// invalidates the rows whose age actually moved rather than every visible row.
    func testPullRequestRowStaysEqualWhenAReferenceDateTickLeavesTheAgeUnchanged() {
        let loader = GitHubAvatarLoader()
        let updatedAt = Date(timeIntervalSince1970: 1_000)
        // Both land in the same whole-hour bucket, so `compactRelativeAge` returns the same text.
        func makeRow(referenceDate: Date) -> PullRequestRow {
            PullRequestRow(
                model: PullRequestRowModel(
                    summary: makePullRequestSummary(number: 1, updatedAt: updatedAt),
                    showsRepository: true,
                    referenceDate: referenceDate
                ),
                isSelected: false,
                avatarLoader: loader,
                onSelect: {}
            )
        }

        let base = updatedAt.addingTimeInterval(3_600)
        XCTAssertEqual(makeRow(referenceDate: base), makeRow(referenceDate: base.addingTimeInterval(60)))
    }

    /// The sectioned list skips rebuilding its rows during the right pane's slide-in, so
    /// its `==` must ignore the action while tracking everything the rows render.
    func testSectionedListEqualityIgnoresTheActionAndComparesRenderedInputs() {
        let loader = GitHubAvatarLoader()
        let date = Date(timeIntervalSince1970: 1_000)
        let sections = [
            PullRequestListSection(id: "all", title: nil, rows: [makePullRequestSummary(number: 1)])
        ]
        let items = PullRequestListItem.flatten(sections, showsRepository: true, referenceDate: date)
        func makeList(
            items: [PullRequestListItem] = items,
            activeDetailID: PullRequestIdentifier? = nil,
            onSelect: @escaping (PullRequestSummary) -> Void = { _ in }
        ) -> PullRequestsSectionedList {
            PullRequestsSectionedList(
                items: items,
                avatarLoader: loader,
                activeDetailID: activeDetailID,
                onSelect: onSelect
            )
        }

        XCTAssertEqual(makeList(), makeList(onSelect: { _ = $0 }))
        XCTAssertNotEqual(makeList(), makeList(activeDetailID: sections[0].rows[0].id))
        XCTAssertNotEqual(makeList(), makeList(items: []))
    }

    /// An untitled section contributes rows only; a titled one leads with its heading. Keyboard
    /// order and the rendered column must stay the same walk of `visibleSections(for:)`.
    func testFlattenEmitsHeadingsOnlyForTitledSections() {
        let date = Date(timeIntervalSince1970: 1_000)
        let items = PullRequestListItem.flatten(
            [
                PullRequestListSection(id: "flat", title: nil, rows: [makePullRequestSummary(number: 1)]),
                PullRequestListSection(id: "titled", title: "Pending review", rows: [makePullRequestSummary(number: 2)])
            ],
            showsRepository: true,
            referenceDate: date
        )

        XCTAssertEqual(items.count, 3)
        guard case .row = items[0] else {
            return XCTFail("An untitled section must contribute rows only")
        }
        guard case .header(_, let title) = items[1] else {
            return XCTFail("A titled section must lead with its heading")
        }
        XCTAssertEqual(title, "Pending review")
        guard case .row = items[2] else {
            return XCTFail("The heading must be followed by its row")
        }
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
        // The merged row has to be visible for the status filter to have something to narrow.
        viewModel.selectStatusFilter(.all)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).count, 2)

        // Not "Alpha" — the shared `octo/alpha` repository name matches that too.
        viewModel.searchQuery = "Beta"
        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).map(\.title), ["Beta"])

        viewModel.searchQuery = ""
        viewModel.selectStatusFilter(.merged)
        XCTAssertEqual(viewModel.visibleSections(for: .all).flatMap(\.rows).map(\.title), ["Beta"])

        viewModel.selectStatusFilter(.all)
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
        viewModel.visibleListCaches = [:]

        _ = viewModel.visibleSections(for: .all)
        XCTAssertNotNil(viewModel.visibleListCaches[.all]?.sections)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.key.tab, .all)

        viewModel.searchQuery = "nothing matches"
        _ = viewModel.visibleSections(for: .all)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.key.searchQuery, "nothing matches")
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.sections, [])
    }

    /// Lazy per-tab loading makes switching tabs routine, and a single-entry memo missed every
    /// time the user alternated between two of them.
    func testEachTabKeepsItsOwnMemoEntryAcrossSwitches() async {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(number: 1, title: "Alpha", isAuthored: true),
                    makePullRequestSummary(number: 2, title: "Beta", isReviewRequested: true)
                ],
                warnings: []
            )
        )
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        let allSections = viewModel.visibleSections(for: .all)
        let authoredSections = viewModel.visibleSections(for: .authored)
        XCTAssertEqual(viewModel.visibleListCaches.keys.sorted(by: { $0.rawValue < $1.rawValue }), [.all, .authored])

        // Both entries survive each other rather than one evicting the other, so coming back to
        // a tab answers from its own entry.
        XCTAssertEqual(viewModel.visibleSections(for: .all), allSections)
        XCTAssertEqual(viewModel.visibleSections(for: .authored), authoredSections)
        XCTAssertEqual(allSections.flatMap(\.rows).map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(authoredSections.flatMap(\.rows).map(\.title), ["Alpha"])
    }

    /// The rendered column memoizes on top of the sections, so a repeat read costs nothing.
    func testVisibleListItemsCacheFillsAndIsServedAgain() async {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(summaries: [makePullRequestSummary(number: 1)], warnings: [])
        )
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()
        viewModel.visibleListCaches = [:]

        let items = viewModel.visibleListItems(for: .all)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.items?.items, items)
        XCTAssertEqual(viewModel.visibleListItems(for: .all), items)
    }

    /// The minute tick must rewrite ages without redoing the filter, sort, and bucket pipeline —
    /// which is why `referenceDate` is stamped on the column rather than folded into the row key.
    /// Counted through the stub's call count rather than wall-clock, like the transcript's
    /// measurement guard.
    func testAReferenceDateTickRefillsTheColumnWithoutReshapingTheRows() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(
                summaries: [makePullRequestSummary(number: 1, updatedAt: currentDate)],
                warnings: []
            )
        )
        let viewModel = makePullRequestsViewModel(service: service, now: { currentDate })
        await viewModel.refresh()

        _ = viewModel.visibleListItems(for: .all)
        let shapedRows = viewModel.visibleListCaches[.all]?.rows
        let key = viewModel.visibleListCaches[.all]?.key

        // Far enough that the rendered age moves from "now" to "1h".
        currentDate = currentDate.addingTimeInterval(3_600)
        viewModel.touchReferenceDate()
        let refreshed = viewModel.visibleListItems(for: .all)

        // The shaped rows are the identical array — the memo key never went stale — while the
        // column was rebuilt against the new clock.
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.key, key)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.rows, shapedRows)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.items?.referenceDate, currentDate)
        // The All tab is sectioned, so the column opens with a heading rather than a row.
        let ages = refreshed.compactMap { item -> String? in
            guard case .row(let model) = item else {
                return nil
            }
            return model.ageText
        }
        XCTAssertEqual(ages, ["1h"])
    }

    /// A shared input changing has to invalidate every tab's entry, not just the visible one.
    func testAnotherTabsMemoEntryRevalidatesAfterASharedInputChanges() async {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(
                summaries: [makePullRequestSummary(number: 1, title: "Alpha", isAuthored: true)],
                warnings: []
            )
        )
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.visibleRows(for: .authored).map(\.title), ["Alpha"])

        viewModel.searchQuery = "nothing matches"
        _ = viewModel.visibleRows(for: .all)

        // `.authored` was memoized before the query and not read since, so its stale entry is
        // still in the dictionary; the key check is what keeps it from being served.
        XCTAssertEqual(viewModel.visibleRows(for: .authored), [])
    }
}
