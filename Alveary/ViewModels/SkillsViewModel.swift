import Foundation
import Observation

enum SkillsPaneTarget: Hashable {
    case newSkill
    case details(String)

    var defaultFocusRestorationID: String {
        switch self {
        case .newSkill:
            "skills-new"
        case .details(let skillID):
            "skills-details-\(skillID)"
        }
    }
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
    private(set) var isRefreshingCatalog = false
    private(set) var activePaneTarget: SkillsPaneTarget?
    private(set) var newSkillSession: NewSkillPaneSession?
    private(set) var detailSessions: [String: SkillDetailsPaneSession] = [:]
    private(set) var pendingPaneDismissals: Set<PaneSessionDismissalRequest<SkillsPaneTarget>> = []
    private(set) var paneDismissalGeneration = 0
    private(set) var paneFocusRestorationID = SkillsPaneTarget.newSkill.defaultFocusRestorationID
    private var deactivatedPaneDismissals: Set<PaneSessionDismissalRequest<SkillsPaneTarget>> = []

    var searchQuery: String = "" {
        didSet {
            search()
        }
    }

    /// Memoized list shaping, owned by `shapedList`. `@ObservationIgnored` so filling
    /// it during a render publishes nothing.
    @ObservationIgnored
    private var listCache: SkillsListCache?

    /// Where the grid was scrolled to, so leaving the screen and coming back lands there; see
    /// ``ScrollOffsetStore`` for why it cannot live on the screen.
    @ObservationIgnored let listScrollOffset = ScrollOffsetStore()

    var filteredInstalled: [Skill] {
        shapedList.installed
    }

    var filteredRecommended: [Skill] {
        shapedList.recommended
    }

    var searchDisplayResults: [Skill] {
        // Leaves `listCache` holding this key's entry, so the dedup below attaches to
        // the lists it was built from.
        let shaped = shapedList
        if let searchDisplay = shaped.searchDisplay {
            return searchDisplay
        }
        let searchDisplay = uniqueSkills(shaped.installed + shaped.recommended + searchResults)
        listCache?.searchDisplay = searchDisplay
        return searchDisplay
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

    func requestNewSkill(focusRestorationID: String? = nil) {
        paneFocusRestorationID = focusRestorationID ?? SkillsPaneTarget.newSkill.defaultFocusRestorationID
        discardCompletedSessionIfNeeded(for: .newSkill)
        if newSkillSession == nil {
            newSkillSession = NewSkillPaneSession(generation: UUID())
        }
        if let generation = newSkillSession?.generation {
            deactivatedPaneDismissals.remove(.init(target: .newSkill, generation: generation))
        }
        activePaneTarget = .newSkill
    }

    func requestDetails(for skill: Skill, focusRestorationID: String? = nil) {
        let target = SkillsPaneTarget.details(skill.id)
        paneFocusRestorationID = focusRestorationID ?? target.defaultFocusRestorationID
        discardCompletedSessionIfNeeded(for: target)
        if let generation = detailSessions[skill.id]?.generation {
            deactivatedPaneDismissals.remove(.init(target: target, generation: generation))
            activePaneTarget = target
            return
        }

        let session = SkillDetailsPaneSession(generation: UUID(), skill: skill)
        detailSessions[skill.id] = session
        activePaneTarget = target
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
            if activePaneTarget == .newSkill {
                paneFocusRestorationID = SkillsPaneTarget.newSkill.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: .newSkill, generation: generation))
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

    func deactivatePane(_ target: SkillsPaneTarget, generation: UUID) {
        guard activePaneTarget == target,
              paneGeneration(for: target) == generation else {
            return
        }
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        pendingPaneDismissals.insert(request)
        deactivatedPaneDismissals.insert(request)
        activePaneTarget = nil
    }

    func dismissActivePane() {
        guard let target = activePaneTarget,
              let generation = paneGeneration(for: target) else {
            return
        }
        dismissPane(target, generation: generation)
    }

    func dismissPane(
        _ target: SkillsPaneTarget,
        generation: UUID,
        restoreFocus: Bool = true
    ) {
        let request = PaneSessionDismissalRequest(target: target, generation: generation)
        guard paneGeneration(for: target) == generation else {
            pendingPaneDismissals.remove(request)
            deactivatedPaneDismissals.remove(request)
            return
        }
        pendingPaneDismissals.remove(request)
        let ownedDeactivation = deactivatedPaneDismissals.remove(request) != nil
        let shouldRestoreFocus = activePaneTarget == target || (ownedDeactivation && activePaneTarget == nil)
        switch target {
        case .newSkill:
            newSkillSession = nil
        case .details(let skillID):
            detailSessions.removeValue(forKey: skillID)
        }
        if activePaneTarget == target {
            activePaneTarget = nil
        }
        if restoreFocus, shouldRestoreFocus {
            paneDismissalGeneration &+= 1
        }
    }

    func paneGeneration(for target: SkillsPaneTarget) -> UUID? {
        switch target {
        case .newSkill:
            newSkillSession?.generation
        case .details(let skillID):
            detailSessions[skillID]?.generation
        }
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
        guard !isRefreshingCatalog else {
            return
        }
        isRefreshingCatalog = true
        defer {
            isRefreshingCatalog = false
        }
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
            if activePaneTarget == .details(skillID),
               !searchDisplayResults.contains(where: { $0.id == skillID }) {
                paneFocusRestorationID = SkillsPaneTarget.newSkill.defaultFocusRestorationID
            }
            pendingPaneDismissals.insert(.init(target: .details(skillID), generation: generation))
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

    /// The three shaped lists the screen renders, computed together so one pass over
    /// `installed` and one over `catalog` serves all of them. `SkillsScreen` asks for
    /// all three in a single body pass, and each `filter` runs a locale-aware
    /// substring match across three fields per skill.
    var shapedList: SkillsListCache {
        // Reads every observable input before the cache check, so `@Observable`
        // dependency registration matches the uncached version.
        let key = SkillsListCacheKey(
            query: normalizedSearchQuery,
            installed: installed,
            catalog: catalog,
            searchResults: searchResults
        )
        if let listCache, listCache.key == key {
            return listCache
        }

        let shaped = SkillsListCache(
            key: key,
            installed: filter(skills: installed),
            recommended: filter(skills: catalog).filter { !$0.isInstalled }
        )
        listCache = shaped
        return shaped
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

    func discardCompletedSessionIfNeeded(for target: SkillsPaneTarget) {
        guard let request = pendingPaneDismissals.first(where: { $0.target == target }) else {
            return
        }
        deactivatedPaneDismissals.remove(request)
        dismissPane(target, generation: request.generation, restoreFocus: false)
    }

    func uniqueSkills(_ skills: [Skill]) -> [Skill] {
        var seenIDs: Set<String> = []
        return skills.filter { skill in
            seenIDs.insert(skill.id).inserted
        }
    }
}

/// The shaped lists for one set of inputs. The combined search display fills in on
/// first use, so a body pass with no active search never pays for the dedup.
private struct SkillsListCache {
    let key: SkillsListCacheKey
    let installed: [Skill]
    let recommended: [Skill]
    var searchDisplay: [Skill]?
}

/// Every input the shaping reads. The arrays compare by shared buffer while the
/// catalog is unchanged, so a cache hit costs no per-skill work.
private struct SkillsListCacheKey: Equatable {
    let query: String
    let installed: [Skill]
    let catalog: [Skill]
    let searchResults: [Skill]
}
