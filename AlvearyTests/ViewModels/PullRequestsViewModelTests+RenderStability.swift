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
}
