import XCTest

@testable import Alveary

/// Search clearing and stale-result rejection after actual service and consumer completion.
@MainActor
extension SkillsViewModelTests {
    func testSearchDiscardsStaleResponsesWhenQueryChangesMidFlight() async throws {
        let service = SkillsMockService(
            installed: [], catalog: [],
            searchResultsByQuery: ["pl": [makeSkill(id: "old")], "pla": [makeSkill(id: "new")]]
        )
        let oldGate = PullRequestsServiceGate()
        defer { oldGate.open() }
        await service.setSearchGate(oldGate, for: "pl")
        let viewModel = SkillsViewModel(skillsService: service)
        viewModel.searchQuery = "pl"
        let oldTask = try XCTUnwrap(viewModel.searchTaskForTesting)
        do {
            try await waitUntil("old search reached its held response") { await service.searchCalls() == ["pl"] }
            XCTAssertTrue(viewModel.isSearchingSkillsSh)
            viewModel.searchQuery = "pla"
            let currentTask = try XCTUnwrap(viewModel.searchTaskForTesting)
            await currentTask.value
            XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
            XCTAssertFalse(viewModel.isSearchingSkillsSh)
        } catch {
            viewModel.searchQuery = ""
            oldGate.open()
            await oldTask.value
            await viewModel.searchTaskForTesting?.value
            throw error
        }
        oldGate.open()
        await oldTask.value
        let calls = await service.searchCalls()
        XCTAssertEqual(calls, ["pl", "pla"])
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
        XCTAssertFalse(viewModel.isSearchingSkillsSh)
    }

    func testSearchClearsProgressAndResultsForShortQuery() async throws {
        let service = SkillsMockService(
            installed: [], catalog: [],
            searchResultsByQuery: ["old": [makeSkill(id: "old")], "pl": [makeSkill(id: "new")]],
            searchDelaysByQuery: ["pl": .seconds(5)]
        )
        let viewModel = SkillsViewModel(skillsService: service)
        viewModel.searchQuery = "old"
        await viewModel.searchTaskForTesting?.value
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["old"])
        viewModel.searchQuery = "pl"
        let pendingTask = try XCTUnwrap(viewModel.searchTaskForTesting)
        do {
            try await waitUntil("replacement search is in flight", timeout: .seconds(1)) {
                await service.searchCalls() == ["old", "pl"] && viewModel.isSearchingSkillsSh
            }
            XCTAssertEqual(viewModel.searchResults.map(\.id), ["old"])
            viewModel.searchQuery = "p"
            XCTAssertFalse(viewModel.isSearchingSkillsSh)
            XCTAssertTrue(viewModel.searchResults.isEmpty)
        } catch {
            viewModel.searchQuery = ""
            await pendingTask.value
            throw error
        }
        await pendingTask.value
    }

    func testSearchEmptyResultsClearProgress() async throws {
        let service = SkillsMockService(installed: [], catalog: [])
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "missing"
        try await waitUntil("empty search completed") {
            await service.searchCalls() == ["missing"] && !viewModel.isSearchingSkillsSh
        }

        XCTAssertFalse(viewModel.isSearchingSkillsSh)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
}
