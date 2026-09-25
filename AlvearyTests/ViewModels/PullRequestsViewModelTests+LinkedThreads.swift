import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    func testLinkedThreadChangesOnlyUpdateMatchingRowPresentation() async throws {
        let service = StubPullRequestsService()
        let linked = makePullRequestSummary(number: 1, isAuthored: true)
        let unlinked = makePullRequestSummary(number: 2, isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [linked, unlinked], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        let original = viewModel.visibleListItems(for: .all)
        let rows = viewModel.visibleRows(for: .all)
        let sections = viewModel.visibleSections(for: .all)
        let listCallCount = service.listCallCount
        let updated = viewModel.visibleListItems(for: .all, linkedThreadIDs: [linked.id])
        let originalModels = rowModels(in: original)
        let updatedModels = rowModels(in: updated)
        let linkedModel = try XCTUnwrap(updatedModels.first { $0.id == linked.id })

        XCTAssertTrue(linkedModel.hasLinkedThread)
        XCTAssertTrue(linkedModel.accessibilityLabel.contains("Linked thread"))
        XCTAssertEqual(updatedModels.map(\.id), originalModels.map(\.id))
        XCTAssertEqual(updatedModels.first { $0.id == unlinked.id }, originalModels.first { $0.id == unlinked.id })
        assertSharesStorage(rows, viewModel.visibleRows(for: .all))
        assertSharesStorage(sections, viewModel.visibleSections(for: .all))
        XCTAssertEqual(service.listCallCount, listCallCount)
        XCTAssertEqual(service.detailCallCount, 0)

        let removed = viewModel.visibleListItems(for: .all, linkedThreadIDs: [])
        XCTAssertEqual(removed, original)
        XCTAssertFalse(rowModels(in: removed).contains { $0.accessibilityLabel.contains("Linked thread") })
    }

    func testLinkedThreadDisplayCacheReusesOutputAndRevalidatesEachTab() async {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 1, isAuthored: true)
        service.listResult = .success(PullRequestListResult(summaries: [summary], warnings: []))
        let viewModel = makePullRequestsViewModel(service: service)
        await viewModel.refresh()

        let originalAll = viewModel.visibleListItems(for: .all)
        let originalAuthored = viewModel.visibleListItems(for: .authored)
        let linkedIDs: Set<PullRequestIdentifier> = [summary.id]
        let linkedAll = viewModel.visibleListItems(for: .all, linkedThreadIDs: linkedIDs)
        let linkedAuthored = viewModel.visibleListItems(for: .authored, linkedThreadIDs: linkedIDs)

        XCTAssertEqual(rowModels(in: linkedAll).map(\.hasLinkedThread), [true])
        XCTAssertEqual(rowModels(in: linkedAuthored).map(\.hasLinkedThread), [true])
        assertSharesStorage(linkedAll, viewModel.visibleListItems(for: .all, linkedThreadIDs: linkedIDs))
        assertSharesStorage(linkedAuthored, viewModel.visibleListItems(for: .authored, linkedThreadIDs: linkedIDs))
        XCTAssertEqual(viewModel.visibleListItems(for: .all), originalAll)
        XCTAssertEqual(viewModel.visibleListItems(for: .authored), originalAuthored)
    }

    func rowModels(in items: [PullRequestListItem]) -> [PullRequestRowModel] {
        items.compactMap { item in
            guard case .row(let model) = item else { return nil }
            return model
        }
    }

    /// Equal contents alone would miss a cache that reallocates and reshapes the list on every read.
    private func assertSharesStorage<Element>(
        _ first: [Element],
        _ second: [Element],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        first.withUnsafeBufferPointer { firstBuffer in
            second.withUnsafeBufferPointer { secondBuffer in
                XCTAssertFalse(firstBuffer.isEmpty, file: file, line: line)
                XCTAssertEqual(firstBuffer.baseAddress, secondBuffer.baseAddress, file: file, line: line)
            }
        }
    }
}
