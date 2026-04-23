import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSkillsScreenNoInstalledSkills() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService(installed: []))
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_no_installed_skills"
        )
    }

    func testSkillsScreenNoSkillsAvailable() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService(installed: [], catalog: []))
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_no_skills_available"
        )
    }

    func testSkillsScreenSearchInFlight() async {
        let viewModel = SkillsViewModel(
            skillsService: SnapshotSkillsService(installed: [], catalog: [], searchResults: [], searchDelay: .seconds(5))
        )
        await viewModel.load()
        viewModel.searchQuery = "browser"
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(viewModel.isSearchingSkillsSh)

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_search_in_flight"
        )
    }

    func testSkillsScreenSearchInFlightWithLocalResults() async {
        let viewModel = SkillsViewModel(
            skillsService: SnapshotSkillsService(searchResults: [], searchDelay: .seconds(5))
        )
        await viewModel.load()
        viewModel.searchQuery = "walkthrough"
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(viewModel.isSearchingSkillsSh)

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_search_in_flight_with_local_results"
        )
    }

    func testSkillsScreenNoSearchResults() async {
        let viewModel = SkillsViewModel(
            skillsService: SnapshotSkillsService(installed: [], catalog: [], searchResults: [])
        )
        await viewModel.load()
        viewModel.searchQuery = "missing"
        try? await Task.sleep(for: .milliseconds(350))

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_no_search_results"
        )
    }

    func testSkillsScreenSearchResults() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService(installed: [], catalog: []))
        await viewModel.load()
        viewModel.searchQuery = "snapshot"
        try? await Task.sleep(for: .milliseconds(350))

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_search_results"
        )
    }

    func testSkillsScreenSearchResultsShowRecommendedWhenRelevant() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService())
        await viewModel.load()
        viewModel.searchQuery = "walkthrough"
        try? await Task.sleep(for: .milliseconds(350))

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_search_results_show_recommended"
        )
    }

    func testSkillsScreenSearchResultsDeduplicateDuplicateIDs() async {
        let duplicate = Skill(
            id: "skill-ui-testing",
            name: "ui-testing",
            description: "No description available.",
            version: nil,
            source: .skillsSh,
            isInstalled: false,
            syncedAgentIDs: [],
            owner: "community",
            repo: "skills",
            sourceUrl: nil,
            installs: 2_047
        )
        let viewModel = SkillsViewModel(
            skillsService: SnapshotSkillsService(
                installed: [],
                catalog: [],
                searchResults: [
                    duplicate,
                    duplicate,
                    Skill(
                        id: "skill-frontend-testing",
                        name: "frontend-testing",
                        description: "No description available.",
                        version: nil,
                        source: .skillsSh,
                        isInstalled: false,
                        syncedAgentIDs: [],
                        owner: "langgenius",
                        repo: "dify",
                        sourceUrl: nil,
                        installs: 1_552
                    )
                ]
            )
        )
        await viewModel.load()
        viewModel.searchQuery = "testing"
        try? await Task.sleep(for: .milliseconds(350))

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_search_results_deduplicate_duplicate_ids"
        )
    }
}
