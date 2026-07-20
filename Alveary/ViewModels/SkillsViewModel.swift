import Foundation
import Observation

enum SkillsPaneTarget: Hashable {
    case newSkill
    case details(String)
}

struct NewSkillDraft: Equatable {
    var name = ""
    var description = ""
    var instructions = ""
}

struct NewSkillPaneSession: Equatable {
    let generation: UUID
    var draft = NewSkillDraft()
    var errorMessage: String?
    var isSubmitting = false
}

struct SkillDetailsPaneSession: Equatable {
    let generation: UUID
    var skill: Skill
    var markdown = ""
    var markdownBaseURL: URL?
    var resolvedGitHubURL: URL?
    var errorMessage: String?
    var isLoading = true
    var isSubmitting = false
}

@MainActor
@Observable
final class SkillsViewModel {
    private let skillsService: any SkillsService
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    private(set) var installed: [Skill] = []
    private(set) var catalog: [Skill] = []
    private(set) var searchResults: [Skill] = []
    private(set) var isSearchingSkillsSh = false
    private(set) var activePaneTarget: SkillsPaneTarget?
    private(set) var newSkillSession: NewSkillPaneSession?
    private(set) var detailSessions: [String: SkillDetailsPaneSession] = [:]
    private(set) var paneDismissalGeneration = 0

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

    var filteredRecommended: [Skill] {
        filteredCatalog.filter { !$0.isInstalled }
    }

    var searchDisplayResults: [Skill] {
        uniqueSkills(filteredInstalled + filteredRecommended + searchResults)
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
        searchGeneration += 1
        isSearchingSkillsSh = false
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        let generation = searchGeneration
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled,
                  let self,
                  self.searchGeneration == generation else {
                return
            }

            self.isSearchingSkillsSh = true
            let results = (try? await self.skillsService.searchSkillsSh(query: query)) ?? []
            guard !Task.isCancelled,
                  self.searchGeneration == generation else {
                return
            }

            self.searchResults = self.uniqueSkills(results.filter { !self.visibleIDs.contains($0.id) })
            self.isSearchingSkillsSh = false
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

    func requestNewSkill() {
        if newSkillSession == nil {
            newSkillSession = NewSkillPaneSession(generation: UUID())
        }
        activePaneTarget = .newSkill
    }

    func requestDetails(for skill: Skill) {
        let target = SkillsPaneTarget.details(skill.id)
        activePaneTarget = target
        guard detailSessions[skill.id] == nil else {
            return
        }

        let session = SkillDetailsPaneSession(generation: UUID(), skill: skill)
        detailSessions[skill.id] = session
        let generation = session.generation
        Task { [weak self] in
            await self?.loadDetails(for: skill, generation: generation)
        }
    }

    func updateNewSkillDraft(_ draft: NewSkillDraft) {
        guard var session = newSkillSession else {
            return
        }
        session.draft = draft
        session.errorMessage = nil
        newSkillSession = session
    }

    func submitNewSkill() async {
        guard activePaneTarget == .newSkill,
              var session = newSkillSession,
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        session.isSubmitting = true
        session.errorMessage = nil
        newSkillSession = session

        do {
            try await create(
                name: session.draft.name,
                description: session.draft.description,
                instructions: session.draft.instructions
            )
            guard newSkillSession?.generation == generation else {
                return
            }
            newSkillSession = nil
            if activePaneTarget == .newSkill {
                activePaneTarget = nil
                paneDismissalGeneration &+= 1
            }
        } catch {
            guard var liveSession = newSkillSession,
                  liveSession.generation == generation else {
                return
            }
            liveSession.isSubmitting = false
            liveSession.errorMessage = error.localizedDescription
            newSkillSession = liveSession
        }
    }

    func installActiveSkill() async {
        await mutateActiveSkill(isUninstall: false)
    }

    func uninstallActiveSkill() async {
        await mutateActiveSkill(isUninstall: true)
    }

    func clearActivePaneError() {
        switch activePaneTarget {
        case .newSkill:
            newSkillSession?.errorMessage = nil
        case .details(let skillID):
            detailSessions[skillID]?.errorMessage = nil
        case nil:
            break
        }
    }

    func deactivatePane() {
        activePaneTarget = nil
    }

    func dismissActivePane() {
        guard let activePaneTarget else {
            return
        }
        switch activePaneTarget {
        case .newSkill:
            newSkillSession = nil
        case .details(let skillID):
            detailSessions.removeValue(forKey: skillID)
        }
        self.activePaneTarget = nil
        paneDismissalGeneration &+= 1
    }

    func fetchSkillMarkdown(for skill: Skill) async throws -> SkillMarkdownDocument {
        let document = try await skillsService.fetchSkillMd(skill: skill)
        return SkillMarkdownDocument(
            markdown: DefaultSkillsService.markdownBody(from: document.markdown),
            baseURL: document.baseURL,
            browserURL: document.browserURL
        )
    }

    func refreshCatalog() async {
        installed = (try? await skillsService.loadInstalled()) ?? []
        catalog = (try? await skillsService.refreshCatalog()) ?? []
        filterVisibleSearchResults()
    }
}

private extension SkillsViewModel {
    func loadDetails(for skill: Skill, generation: UUID) async {
        do {
            let document = try await fetchSkillMarkdown(for: skill)
            guard var session = detailSessions[skill.id],
                  session.generation == generation else {
                return
            }
            session.markdown = document.markdown
            session.markdownBaseURL = document.baseURL
            session.resolvedGitHubURL = document.browserURL ?? skill.githubURL
            session.isLoading = false
            detailSessions[skill.id] = session
        } catch {
            guard var session = detailSessions[skill.id],
                  session.generation == generation else {
                return
            }
            session.markdown = skill.description
            session.markdownBaseURL = nil
            session.resolvedGitHubURL = skill.githubURL
            session.errorMessage = error.localizedDescription
            session.isLoading = false
            detailSessions[skill.id] = session
        }
    }

    func mutateActiveSkill(isUninstall: Bool) async {
        guard case .details(let skillID) = activePaneTarget,
              var session = detailSessions[skillID],
              !session.isSubmitting else {
            return
        }
        let generation = session.generation
        let skill = session.skill
        session.isSubmitting = true
        session.errorMessage = nil
        detailSessions[skillID] = session

        do {
            if isUninstall {
                try await uninstall(skill)
            } else {
                try await install(skill)
            }
            guard detailSessions[skillID]?.generation == generation else {
                return
            }
            detailSessions.removeValue(forKey: skillID)
            if activePaneTarget == .details(skillID) {
                activePaneTarget = nil
                paneDismissalGeneration &+= 1
            }
        } catch {
            guard var liveSession = detailSessions[skillID],
                  liveSession.generation == generation else {
                return
            }
            liveSession.isSubmitting = false
            liveSession.errorMessage = error.localizedDescription
            detailSessions[skillID] = liveSession
        }
    }

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
        searchResults = uniqueSkills(searchResults.filter { !visibleIDs.contains($0.id) })
    }

    func uniqueSkills(_ skills: [Skill]) -> [Skill] {
        var seenIDs: Set<String> = []
        return skills.filter { skill in
            seenIDs.insert(skill.id).inserted
        }
    }
}
