import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SkillsViewModelTests {
    // MARK: - List memoization

    func testShapedListsRekeyWhenTheSearchQueryChanges() async {
        let alpha = makeSkill(id: "alpha")
        let beta = makeSkill(id: "beta")
        let viewModel = SkillsViewModel(
            skillsService: SkillsMockService(installed: [alpha, beta], catalog: [])
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.filteredInstalled.map(\.id), ["alpha", "beta"])

        viewModel.searchQuery = "beta"

        XCTAssertEqual(viewModel.filteredInstalled.map(\.id), ["beta"])
        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["beta"])
    }

    func testShapedListsRekeyWhenAMutationReplacesTheInstalledSkills() async throws {
        let installed = makeSkill(id: "alpha")
        let catalogEntry = makeSkill(id: "beta", source: .catalog, isInstalled: false)
        let service = SkillsMockService(installed: [installed], catalog: [catalogEntry])
        let viewModel = SkillsViewModel(skillsService: service)
        await viewModel.load()

        XCTAssertEqual(viewModel.filteredInstalled.map(\.id), ["alpha"])
        XCTAssertEqual(viewModel.filteredRecommended.map(\.id), ["beta"])

        await service.setInstalledAfterMutation([installed, makeSkill(id: "beta", source: .catalog)])
        await service.setCatalogAfterMutation([makeSkill(id: "beta", source: .catalog)])
        try await viewModel.install(catalogEntry)

        XCTAssertEqual(viewModel.filteredInstalled.map(\.id), ["alpha", "beta"])
        // Now installed, so it leaves the recommended bucket.
        XCTAssertTrue(viewModel.filteredRecommended.isEmpty)
    }

    /// The combined list is the one shaping step the cache defers, so it has to compose
    /// correctly whether or not the other two were read first, and stay stable once filled.
    func testSearchDisplayResultsFillLazilyAndStayStableAcrossReads() async {
        let service = SkillsMockService(
            installed: [makeSkill(id: "installed")],
            catalog: [makeSkill(id: "other", source: .catalog, isInstalled: false)]
        )
        let viewModel = SkillsViewModel(skillsService: service)
        await viewModel.load()

        // Reading the other shaped lists first leaves the combined list unfilled.
        _ = viewModel.filteredInstalled
        _ = viewModel.filteredRecommended

        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["installed", "other"])
        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["installed", "other"])
    }

    /// A fresh view model reads the combined list first, so the deferred step must build
    /// its own inputs rather than depend on an earlier read having filled the cache.
    func testSearchDisplayResultsComposeWithoutAPriorShapedListRead() async {
        let service = SkillsMockService(
            installed: [makeSkill(id: "installed")],
            catalog: [makeSkill(id: "other", source: .catalog, isInstalled: false)]
        )
        let viewModel = SkillsViewModel(skillsService: service)
        await viewModel.load()

        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["installed", "other"])
    }

    func testSearchDisplayResultsRekeyWhenRemoteSearchResultsLand() async {
        let installed = makeSkill(id: "playwright-cli")
        let service = SkillsMockService(
            installed: [installed],
            catalog: [],
            searchResultsByQuery: ["playwright": [makeSkill(id: "remote", source: .skillsSh)]]
        )
        let viewModel = SkillsViewModel(skillsService: service)
        await viewModel.load()

        viewModel.searchQuery = "playwright"
        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["playwright-cli"])

        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["playwright-cli", "remote"])
    }

    // MARK: - Render stability

    func testSkillsPaneEqualityIgnoresTheDismissActionAndComparesTheTarget() {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        let other = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        let pane = SkillsPane(viewModel: viewModel, target: .details("alpha"), onDismiss: {})

        XCTAssertEqual(
            pane,
            SkillsPane(viewModel: viewModel, target: .details("alpha"), onDismiss: { XCTFail("unused") })
        )
        XCTAssertNotEqual(pane, SkillsPane(viewModel: viewModel, target: .details("beta"), onDismiss: {}))
        XCTAssertNotEqual(pane, SkillsPane(viewModel: viewModel, target: .newSkill, onDismiss: {}))
        XCTAssertNotEqual(pane, SkillsPane(viewModel: other, target: .details("alpha"), onDismiss: {}))
    }

    func testSkillCardEqualityIgnoresItsActionsAndComparesTheRenderedSkill() throws {
        let skill = makeSkill(id: "alpha")
        let card = try makeCard(skill: skill)

        XCTAssertEqual(card, try makeCard(skill: skill))
        XCTAssertNotEqual(card, try makeCard(skill: makeSkill(id: "alpha", isInstalled: false)))
        XCTAssertNotEqual(card, try makeCard(skill: makeSkill(id: "beta")))
        XCTAssertNotEqual(card, try makeCard(skill: skill, focusID: "skills-details-beta"))
        XCTAssertNotEqual(card, try makeCard(skill: skill, isSelected: true))
    }
}

/// `SkillCard` stores a `FocusState` binding, which `hostedFocusStateBinding()` vends from a real
/// body pass; the binding is excluded from `==`, so any live one serves.
@MainActor
private func makeCard(
    skill: Skill,
    isSelected: Bool = false,
    focusID: String = "skills-details-alpha"
) throws -> SkillCard {
    SkillCard(
        skill: skill,
        isSelected: isSelected,
        onOpen: {},
        onPrimaryAction: {},
        cardFocus: try hostedFocusStateBinding(String.self),
        cardFocusID: focusID
    )
}
