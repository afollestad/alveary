import Foundation
import XCTest

@testable import Alveary

@MainActor
final class SkillsViewModelTests: XCTestCase {
    func testLoadPopulatesInstalledBeforeCatalog() async {
        let service = SkillsMockService(
            installed: [makeSkill(id: "installed")],
            catalog: [makeSkill(id: "catalog", source: .catalog)]
        )
        await service.blockCatalogLoad()
        let viewModel = SkillsViewModel(skillsService: service)

        let task = Task {
            await viewModel.load()
        }

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.installed.map(\.id), ["installed"])
        XCTAssertTrue(viewModel.catalog.isEmpty)

        await service.resumeCatalogLoad()
        await task.value
        XCTAssertEqual(viewModel.catalog.map(\.id), ["catalog"])
    }

    func testSearchDebouncesAndFiltersVisibleIDs() async {
        let installed = makeSkill(id: "playwright-cli")
        let service = SkillsMockService(
            installed: [installed],
            catalog: [],
            searchResultsByQuery: [
                "pl": [installed, makeSkill(id: "new-skill", source: .skillsSh)]
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        await viewModel.load()
        viewModel.searchQuery = "pl"
        try? await Task.sleep(for: .milliseconds(550))
        let searchCalls = await service.searchCalls()

        XCTAssertEqual(searchCalls, ["pl"])
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new-skill"])
    }

    func testSearchDiscardsStaleResponsesWhenQueryChangesMidFlight() async {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "pl": [makeSkill(id: "old")],
                "pla": [makeSkill(id: "new")]
            ],
            searchDelaysByQuery: [
                "pl": .milliseconds(300),
                "pla": .zero
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "pl"
        try? await Task.sleep(for: .milliseconds(450))
        viewModel.searchQuery = "pla"
        try? await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
    }

    func testFilteredCollectionsMatchLocalSearchQuery() async {
        let service = SkillsMockService(
            installed: [makeSkill(id: "playwright-local")],
            catalog: [
                makeSkill(id: "browser-automation", source: .catalog, isInstalled: false),
                makeSkill(id: "terminal-tools", source: .catalog, isInstalled: false)
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        await viewModel.load()
        viewModel.searchQuery = "browser"

        XCTAssertTrue(viewModel.filteredInstalled.isEmpty)
        XCTAssertEqual(viewModel.filteredCatalog.map(\.id), ["browser-automation"])
        XCTAssertTrue(viewModel.hasActiveSearch)
    }

    func testInstallReloadsState() async throws {
        let skill = makeSkill(id: "playwright", source: .catalog)
        let service = SkillsMockService(installed: [], catalog: [skill])
        let viewModel = SkillsViewModel(skillsService: service)

        await viewModel.load()
        await service.setInstalledAfterMutation([makeSkill(id: "playwright")])
        await service.setCatalogAfterMutation([makeSkill(id: "playwright", source: .catalog, isInstalled: true)])

        try await viewModel.install(skill)

        XCTAssertEqual(viewModel.installed.map(\.id), ["playwright"])
        XCTAssertTrue(viewModel.catalog.first?.isInstalled == true)
    }

    func testFetchSkillMarkdownStripsFrontmatterAndPreservesBaseURL() async throws {
        let baseURL = URL(fileURLWithPath: "/tmp/skills/example", isDirectory: true)
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            fetchedMarkdownDocument: SkillMarkdownDocument(
                markdown: "---\nname: \"example\"\ndescription: \"desc\"\n---\n\nSee [notes](references/file.md).",
                baseURL: baseURL
            )
        )
        let viewModel = SkillsViewModel(skillsService: service)

        let document = try await viewModel.fetchSkillMarkdown(for: makeSkill(id: "example"))

        XCTAssertEqual(document.markdown, "See [notes](references/file.md).")
        XCTAssertEqual(document.baseURL, baseURL)
    }
}

private actor SkillsMockService: SkillsService {
    private let installed: [Skill]
    private let catalog: [Skill]
    private let searchResultsByQuery: [String: [Skill]]
    private let searchDelaysByQuery: [String: Duration]
    private let fetchedMarkdownDocument: SkillMarkdownDocument

    private var installedAfterMutation: [Skill]?
    private var catalogAfterMutation: [Skill]?
    private var searchQueryCalls: [String] = []
    private var shouldBlockCatalogLoad = false
    private var catalogContinuation: CheckedContinuation<Void, Never>?

    init(
        installed: [Skill],
        catalog: [Skill],
        searchResultsByQuery: [String: [Skill]] = [:],
        searchDelaysByQuery: [String: Duration] = [:],
        fetchedMarkdownDocument: SkillMarkdownDocument = SkillMarkdownDocument(markdown: "", baseURL: nil)
    ) {
        self.installed = installed
        self.catalog = catalog
        self.searchResultsByQuery = searchResultsByQuery
        self.searchDelaysByQuery = searchDelaysByQuery
        self.fetchedMarkdownDocument = fetchedMarkdownDocument
    }

    func loadInstalled() async throws -> [Skill] {
        installedAfterMutation ?? installed
    }

    func loadCatalog() async throws -> [Skill] {
        if shouldBlockCatalogLoad {
            await withCheckedContinuation { continuation in
                catalogContinuation = continuation
            }
        }
        return catalogAfterMutation ?? catalog
    }

    func searchSkillsSh(query: String) async throws -> [Skill] {
        searchQueryCalls.append(query)
        if let delay = searchDelaysByQuery[query], delay != .zero {
            try await Task.sleep(for: delay)
        }
        return searchResultsByQuery[query] ?? []
    }

    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument {
        fetchedMarkdownDocument
    }

    func install(_ skill: Skill) async throws {}

    func uninstall(_ skill: Skill) async throws {}

    func create(name: String, description: String, instructions: String) async throws {}

    func refreshCatalog() async throws -> [Skill] {
        catalogAfterMutation ?? catalog
    }

    func blockCatalogLoad() {
        shouldBlockCatalogLoad = true
    }

    func resumeCatalogLoad() {
        shouldBlockCatalogLoad = false
        catalogContinuation?.resume()
        catalogContinuation = nil
    }

    func setInstalledAfterMutation(_ skills: [Skill]) {
        installedAfterMutation = skills
    }

    func setCatalogAfterMutation(_ skills: [Skill]) {
        catalogAfterMutation = skills
    }

    func searchCalls() -> [String] {
        searchQueryCalls
    }
}

private func makeSkill(
    id: String,
    source: Skill.Source = .local,
    isInstalled: Bool = true,
    description: String? = nil
) -> Skill {
    Skill(
        id: id,
        name: id,
        description: description ?? id,
        version: nil,
        source: source,
        isInstalled: isInstalled,
        syncedAgentIDs: [],
        owner: nil,
        repo: nil,
        sourceUrl: nil,
        installs: nil
    )
}
