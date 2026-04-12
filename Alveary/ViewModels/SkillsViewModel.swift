import Foundation
import Observation

@MainActor
@Observable
final class SkillsViewModel {
    private let skillsService: any SkillsService
    private var searchTask: Task<Void, Never>?

    private(set) var installed: [Skill] = []
    private(set) var catalog: [Skill] = []
    private(set) var searchResults: [Skill] = []

    var searchQuery: String = "" {
        didSet {
            search()
        }
    }

    var filteredInstalled: [Skill] {
        filter(skills: installed)
    }

    var filteredCatalog: [Skill] {
        filter(skills: catalog)
    }

    var hasActiveSearch: Bool {
        !normalizedSearchQuery.isEmpty
    }

    init(skillsService: any SkillsService) {
        self.skillsService = skillsService
    }

    deinit {
        MainActor.assumeIsolated {
            searchTask?.cancel()
        }
    }

    func load() async {
        installed = (try? await skillsService.loadInstalled()) ?? []
        catalog = (try? await skillsService.loadCatalog()) ?? []
        filterVisibleSearchResults()
    }

    func search() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled,
                  let self else {
                return
            }

            let results = (try? await self.skillsService.searchSkillsSh(query: query)) ?? []
            guard !Task.isCancelled else {
                return
            }

            self.searchResults = results.filter { !self.visibleIDs.contains($0.id) }
        }
    }

    func install(_ skill: Skill) async throws {
        try await skillsService.install(skill)
        await reloadAfterMutation(refreshCatalog: false)
    }

    func uninstall(_ skill: Skill) async throws {
        try await skillsService.uninstall(skill)
        await reloadAfterMutation(refreshCatalog: false)
    }

    func create(name: String, description: String, instructions: String) async throws {
        try await skillsService.create(name: name, description: description, instructions: instructions)
        await reloadAfterMutation(refreshCatalog: false)
    }

    func fetchSkillMarkdown(for skill: Skill) async throws -> SkillMarkdownDocument {
        let document = try await skillsService.fetchSkillMd(skill: skill)
        return SkillMarkdownDocument(
            markdown: DefaultSkillsService.markdownBody(from: document.markdown),
            baseURL: document.baseURL
        )
    }

    func refreshCatalog() async {
        installed = (try? await skillsService.loadInstalled()) ?? []
        catalog = (try? await skillsService.refreshCatalog()) ?? []
        filterVisibleSearchResults()
    }
}

private extension SkillsViewModel {
    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var visibleIDs: Set<String> {
        Set(installed.map(\.id)).union(catalog.map(\.id))
    }

    func filter(skills: [Skill]) -> [Skill] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else {
            return skills
        }

        return skills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query)
                || skill.id.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
        }
    }

    func reloadAfterMutation(refreshCatalog: Bool) async {
        installed = (try? await skillsService.loadInstalled()) ?? []
        if refreshCatalog {
            catalog = (try? await skillsService.refreshCatalog()) ?? []
        } else {
            catalog = (try? await skillsService.loadCatalog()) ?? []
        }
        filterVisibleSearchResults()
    }

    func filterVisibleSearchResults() {
        searchResults = searchResults.filter { !visibleIDs.contains($0.id) }
    }
}
