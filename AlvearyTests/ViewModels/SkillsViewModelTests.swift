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
        try? await Task.sleep(for: .milliseconds(350))
        let searchCalls = await service.searchCalls()

        XCTAssertEqual(searchCalls, ["pl"])
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new-skill"])
    }

    func testSearchDoesNotCallSkillsShBeforeDebounceDelay() async {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "pl": [makeSkill(id: "new-skill", source: .skillsSh)]
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "pl"
        try? await Task.sleep(for: .milliseconds(150))
        let earlySearchCalls = await service.searchCalls()

        XCTAssertTrue(earlySearchCalls.isEmpty)

        try? await Task.sleep(for: .milliseconds(150))
        let settledSearchCalls = await service.searchCalls()

        XCTAssertEqual(settledSearchCalls, ["pl"])
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
        try? await Task.sleep(for: .milliseconds(350))
        viewModel.searchQuery = "pla"
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
        XCTAssertFalse(viewModel.isSearchingSkillsSh)
    }

    func testSearchCancelsInFlightSkillsShRequestWhenQueryChanges() async {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "pl": [makeSkill(id: "old")],
                "pla": [makeSkill(id: "new")]
            ],
            searchDelaysByQuery: [
                "pl": .seconds(5),
                "pla": .zero
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "pl"
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(viewModel.isSearchingSkillsSh)

        viewModel.searchQuery = "pla"
        try? await Task.sleep(for: .milliseconds(100))
        let cancelledSearchCalls = await service.cancelledSearchCalls()

        XCTAssertEqual(cancelledSearchCalls, ["pl"])
        XCTAssertFalse(viewModel.isSearchingSkillsSh)

        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
    }

    func testSearchTracksSkillsShRequestProgress() async {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "pl": [makeSkill(id: "new")]
            ],
            searchDelaysByQuery: [
                "pl": .milliseconds(300)
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "pl"
        XCTAssertFalse(viewModel.isSearchingSkillsSh)

        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(viewModel.isSearchingSkillsSh)

        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(viewModel.isSearchingSkillsSh)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["new"])
    }

    func testSearchClearsProgressAndResultsForShortQuery() async {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "pl": [makeSkill(id: "new")]
            ],
            searchDelaysByQuery: [
                "pl": .milliseconds(300)
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "pl"
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(viewModel.isSearchingSkillsSh)

        viewModel.searchQuery = "p"
        XCTAssertFalse(viewModel.isSearchingSkillsSh)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearchEmptyResultsClearProgress() async {
        let service = SkillsMockService(installed: [], catalog: [])
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "missing"
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertFalse(viewModel.isSearchingSkillsSh)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearchDeduplicatesDuplicateSkillsShResults() async {
        let duplicate = makeSkill(id: "ui-testing", source: .skillsSh, isInstalled: false)
        let unique = makeSkill(id: "snapshot-testing", source: .skillsSh, isInstalled: false)
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            searchResultsByQuery: [
                "te": [duplicate, duplicate, unique]
            ]
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.searchQuery = "te"
        try? await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(viewModel.searchResults.map(\.id), ["ui-testing", "snapshot-testing"])
        XCTAssertEqual(viewModel.searchDisplayResults.map(\.id), ["ui-testing", "snapshot-testing"])
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
                baseURL: baseURL,
                browserURL: URL(string: "https://github.com/example/skills/blob/main/example/SKILL.md")
            )
        )
        let viewModel = SkillsViewModel(skillsService: service)

        let document = try await viewModel.fetchSkillMarkdown(for: makeSkill(id: "example"))

        XCTAssertEqual(document.markdown, "See [notes](references/file.md).")
        XCTAssertEqual(document.baseURL, baseURL)
        XCTAssertEqual(document.browserURL, URL(string: "https://github.com/example/skills/blob/main/example/SKILL.md"))
    }

    func testPaneSessionsRestoreNewSkillDraftAfterViewingDetails() async throws {
        let skill = makeSkill(id: "details")
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [skill], catalog: []))

        viewModel.requestNewSkill()
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "cached-skill",
            description: "Cached description",
            instructions: "Cached instructions"
        ))
        viewModel.requestDetails(for: skill)
        viewModel.requestNewSkill()

        XCTAssertEqual(viewModel.newSkillSession?.draft.name, "cached-skill")
        XCTAssertEqual(viewModel.detailSessions[skill.id]?.skill.id, skill.id)
    }

    func testDismissedDetailLoadCannotRecreateSession() async {
        let skill = makeSkill(id: "slow-details")
        let service = SkillsMockService(
            installed: [skill],
            catalog: [],
            fetchDelay: .milliseconds(200)
        )
        let viewModel = SkillsViewModel(skillsService: service)

        viewModel.requestDetails(for: skill)
        viewModel.dismissActivePane()
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(viewModel.detailSessions[skill.id])
    }

    func testDelayedCreateCannotMutateReopenedTargetGeneration() async throws {
        let service = SkillsMockService(
            installed: [],
            catalog: [],
            createDelay: .milliseconds(200)
        )
        let viewModel = SkillsViewModel(skillsService: service)
        viewModel.requestNewSkill()
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "original",
            description: "Original",
            instructions: "Original instructions"
        ))

        let submission = Task { await viewModel.submitNewSkill() }
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.dismissActivePane()
        viewModel.requestNewSkill()
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "reopened",
            description: "Reopened",
            instructions: "Reopened instructions"
        ))
        let reopenedGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)

        await submission.value

        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertEqual(viewModel.newSkillSession?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.newSkillSession?.draft.name, "reopened")
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }

    func testDelayedInstallCannotClearReopenedDetailGeneration() async throws {
        let skill = makeSkill(id: "delayed-install")
        let service = SkillsMockService(
            installed: [],
            catalog: [skill],
            installDelay: .milliseconds(200)
        )
        let viewModel = SkillsViewModel(skillsService: service)
        viewModel.requestDetails(for: skill)

        let submission = Task { await viewModel.installActiveSkill() }
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.dismissActivePane()
        viewModel.requestDetails(for: skill)
        let reopenedGeneration = try XCTUnwrap(viewModel.detailSessions[skill.id]?.generation)

        await submission.value

        XCTAssertEqual(viewModel.activePaneTarget, .details(skill.id))
        XCTAssertEqual(viewModel.detailSessions[skill.id]?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }
}

private actor SkillsMockService: SkillsService {
    private let installed: [Skill]
    private let catalog: [Skill]
    private let searchResultsByQuery: [String: [Skill]]
    private let searchDelaysByQuery: [String: Duration]
    private let fetchedMarkdownDocument: SkillMarkdownDocument
    private let fetchDelay: Duration
    private let createDelay: Duration
    private let installDelay: Duration

    private var installedAfterMutation: [Skill]?
    private var catalogAfterMutation: [Skill]?
    private var searchQueryCalls: [String] = []
    private var cancelledSearchQueryCalls: [String] = []
    private var shouldBlockCatalogLoad = false
    private var catalogContinuation: CheckedContinuation<Void, Never>?

    init(
        installed: [Skill],
        catalog: [Skill],
        searchResultsByQuery: [String: [Skill]] = [:],
        searchDelaysByQuery: [String: Duration] = [:],
        fetchedMarkdownDocument: SkillMarkdownDocument = SkillMarkdownDocument(markdown: "", baseURL: nil, browserURL: nil),
        fetchDelay: Duration = .zero,
        createDelay: Duration = .zero,
        installDelay: Duration = .zero
    ) {
        self.installed = installed
        self.catalog = catalog
        self.searchResultsByQuery = searchResultsByQuery
        self.searchDelaysByQuery = searchDelaysByQuery
        self.fetchedMarkdownDocument = fetchedMarkdownDocument
        self.fetchDelay = fetchDelay
        self.createDelay = createDelay
        self.installDelay = installDelay
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
        do {
            if let delay = searchDelaysByQuery[query], delay != .zero {
                try await Task.sleep(for: delay)
            }
        } catch is CancellationError {
            cancelledSearchQueryCalls.append(query)
            throw CancellationError()
        }
        return searchResultsByQuery[query] ?? []
    }

    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument {
        if fetchDelay != .zero {
            try await Task.sleep(for: fetchDelay)
        }
        return fetchedMarkdownDocument
    }

    func install(_ skill: Skill) async throws {
        if installDelay != .zero {
            try await Task.sleep(for: installDelay)
        }
    }

    func uninstall(_ skill: Skill) async throws {}

    func create(name: String, description: String, instructions: String) async throws {
        if createDelay != .zero {
            try await Task.sleep(for: createDelay)
        }
    }

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

    func cancelledSearchCalls() -> [String] {
        cancelledSearchQueryCalls
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
