import XCTest

@testable import Alveary

/// The search field publishes per keystroke, but reshaping the list per keystroke re-ran the
/// filter, sort, and bucket pipeline for every intermediate query. These cover the split between
/// what the field shows and what the list shapes from.
@MainActor
extension PullRequestsViewModelTests {
    func testTheFieldTracksEveryKeystrokeWhileTheListWaitsForThePause() async {
        let viewModel = await makeSearchViewModel(debounce: .milliseconds(5))

        for query in ["r", "re", "rel"] {
            viewModel.searchQuery = query
        }

        // Every keystroke is on screen immediately; none of them has narrowed the list yet.
        XCTAssertEqual(viewModel.searchQuery, "rel")
        XCTAssertEqual(viewModel.activeSearchQuery, "")
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.title), ["Alpha", "Release notes"])
        XCTAssertFalse(viewModel.hasActiveNarrowing)

        await waitForSearchCommit(viewModel, toEqual: "rel")
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.title), ["Release notes"])
        XCTAssertTrue(viewModel.hasActiveNarrowing)
    }

    /// The whole point of the debounce: a burst commits once, at the end, rather than once per
    /// character typed through it.
    func testABurstOfKeystrokesCommitsOnlyItsFinalQuery() async {
        var committed: [String] = []
        let viewModel = await makeSearchViewModel(debounce: .milliseconds(5))

        for query in ["r", "re", "rel"] {
            viewModel.searchQuery = query
            committed.append(viewModel.activeSearchQuery)
        }
        await waitForSearchCommit(viewModel, toEqual: "rel")
        committed.append(viewModel.activeSearchQuery)

        XCTAssertEqual(committed, ["", "", "", "rel"])
    }

    /// Retyping the same text — selecting the field's contents and typing them again — must not
    /// republish, or the memo is invalidated for an identical result.
    func testReassigningTheSameQueryCommitsNothingNew() async {
        let viewModel = await makeSearchViewModel(debounce: .zero)

        viewModel.searchQuery = "release"
        let rows = viewModel.visibleRows(for: .all)
        let cachedKey = viewModel.visibleListCaches[.all]?.key

        viewModel.searchQuery = "release"

        XCTAssertEqual(viewModel.visibleRows(for: .all), rows)
        XCTAssertEqual(viewModel.visibleListCaches[.all]?.key, cachedKey)
    }

    /// Surrounding whitespace is trimmed once at commit rather than per row per pass, so typing
    /// a trailing space onto a committed query must not reshape the list.
    func testTrailingWhitespaceDoesNotRecommitTheQuery() async {
        let viewModel = await makeSearchViewModel(debounce: .zero)

        viewModel.searchQuery = "release"
        viewModel.searchQuery = "release "

        XCTAssertEqual(viewModel.searchQuery, "release ")
        XCTAssertEqual(viewModel.activeSearchQuery, "release")
        XCTAssertEqual(viewModel.visibleRows(for: .all).map(\.title), ["Release notes"])
    }

    // MARK: - Private

    private func makeSearchViewModel(debounce: Duration) async -> PullRequestsViewModel {
        let service = StubPullRequestsService()
        service.listResult = .success(
            PullRequestListResult(
                summaries: [
                    makePullRequestSummary(number: 1, title: "Alpha", updatedAt: Date(timeIntervalSince1970: 2_000)),
                    makePullRequestSummary(number: 2, title: "Release notes")
                ],
                warnings: []
            )
        )
        let viewModel = makePullRequestsViewModel(service: service, searchDebounce: debounce)
        // The packaged `.open` status is a narrowing of its own, so widening it first lets
        // `hasActiveNarrowing` report the search alone.
        viewModel.selectStatusFilter(.all)
        await viewModel.refresh()
        return viewModel
    }

    /// Polls with real sleeps rather than `waitFor`'s yields, since what is being waited on is a
    /// wall-clock `Task.sleep` and not main-actor work.
    private func waitForSearchCommit(
        _ viewModel: PullRequestsViewModel,
        toEqual query: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<400 {
            if viewModel.activeSearchQuery == query {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Search never committed \"\(query)\"", file: file, line: line)
    }
}
