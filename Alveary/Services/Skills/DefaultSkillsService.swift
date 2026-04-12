import Foundation

actor DefaultSkillsService: SkillsService {
    private let baseDir: URL
    private let cacheDir: URL
    private let session: URLSession
    private let bundle: Bundle
    private let agentRegistry: AgentRegistry
    private let sharedSkillsDirectories: [String]
    private var catalogCache: CatalogIndex?
    private var defaultBranchCache: [String: (branch: String, fetchedAt: Date)] = [:]
    private var treeCache: [String: (entries: [GitTreeEntry], fetchedAt: Date)] = [:]

    private static let catalogVersion = 1
    private static let repoCacheTTL: TimeInterval = 600

    init(
        baseDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agentskills"),
        session: URLSession = .shared,
        bundle: Bundle = .main,
        sharedSkillsDirectories: [String] = ["~/.agents/skills"],
        agentRegistry: AgentRegistry
    ) {
        self.baseDir = baseDir
        self.cacheDir = baseDir.appendingPathComponent(".alveary")
        self.session = session
        self.bundle = bundle
        self.sharedSkillsDirectories = sharedSkillsDirectories
        self.agentRegistry = agentRegistry
    }

    func loadInstalled() async throws -> [Skill] {
        var seenIDs: Set<String> = []
        var skills = scanDirectory(baseDir, seenIDs: &seenIDs)

        for target in discoveryTargets {
            let directory = URL(fileURLWithPath: (target.skillsDirectory as NSString).expandingTildeInPath)
            skills.append(contentsOf: scanDirectory(directory, seenIDs: &seenIDs))
        }

        return sortSkills(skills)
    }

    func loadCatalog() async throws -> [Skill] {
        if let catalogCache {
            return await mergeInstalledState(mapCatalog(catalogCache))
        }

        let cacheFile = cacheDir.appendingPathComponent("catalog-index.json")
        if let data = try? Data(contentsOf: cacheFile),
           let index = try? JSONDecoder().decode(CatalogIndex.self, from: data),
           index.version == Self.catalogVersion {
            catalogCache = index
            return await mergeInstalledState(mapCatalog(index))
        }

        do {
            return try await refreshCatalog()
        } catch {
            guard let bundled = loadBundledCatalog() else {
                throw error
            }
            catalogCache = bundled
            return await mergeInstalledState(mapCatalog(bundled))
        }
    }

    func searchSkillsSh(query: String) async throws -> [Skill] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            return []
        }

        let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery
        guard let url = URL(string: "https://skills.sh/api/search?q=\(encodedQuery)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(SkillsShResponse.self, from: data)

        let skills = response.skills.map { entry in
            let parts = entry.source.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            return Skill(
                id: entry.skillId,
                name: entry.name,
                description: "",
                version: nil,
                source: .skillsSh,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: parts.first.map(String.init),
                repo: parts.dropFirst().first.map(String.init),
                sourceUrl: nil,
                installs: entry.installs
            )
        }

        return sortSkills(skills)
    }

    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument {
        if let localMarkdown = loadLocalSkillMarkdownDocument(skillID: skill.id) {
            return localMarkdown
        }

        guard let owner = skill.owner, let repo = skill.repo else {
            throw SkillsError.noSource(skill.id)
        }

        let branch = try await defaultBranch(owner: owner, repo: repo)
        if let fallbackMarkdown = try await Self.fetchFallbackSkillMarkdown(
            owner: owner,
            repo: repo,
            branch: branch,
            skillID: skill.id,
            session: session
        ) {
            return fallbackMarkdown
        }

        if let discoveredMarkdown = try await fetchTreeDiscoveredSkillMarkdown(
            owner: owner,
            repo: repo,
            branch: branch,
            skill: skill
        ) {
            return discoveredMarkdown
        }

        return Self.defaultMarkdownDocument(for: skill)
    }

    func install(_ skill: Skill) async throws {
        let content = try await fetchSkillMd(skill: skill)
        let skillDirectory = baseDir.appendingPathComponent(skill.id, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true, attributes: nil)
        try content.markdown.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        sync(skillID: skill.id, to: detectedAgents())
        catalogCache = nil
    }

    func uninstall(_ skill: Skill) async throws {
        let skillDirectory = baseDir.appendingPathComponent(skill.id, isDirectory: true)
        try? FileManager.default.removeItem(at: skillDirectory)

        for target in discoveryTargets {
            let link = URL(fileURLWithPath: (target.skillsDirectory as NSString).expandingTildeInPath)
                .appendingPathComponent(skill.id)
            try? FileManager.default.removeItem(at: link)
        }

        catalogCache = nil
    }

    func create(name: String, description: String, instructions: String) async throws {
        let pattern = "^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$"
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw SkillsError.invalidName(name)
        }

        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDescription = description.replacingOccurrences(of: "\"", with: "\\\"")
        let content = [
            "---",
            "name: \"\(escapedName)\"",
            "description: \"\(escapedDescription)\"",
            "version: 1.0.0",
            "---",
            "",
            instructions
        ].joined(separator: "\n")

        let skillDirectory = baseDir.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true, attributes: nil)
        try content.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        sync(skillID: name, to: detectedAgents())
        catalogCache = nil
    }

    @discardableResult
    func refreshCatalog() async throws -> [Skill] {
        let catalogSkills: [CatalogSkillEntry]
        do {
            catalogSkills = try await fetchCatalogRepo(owner: "anthropics", repo: "skills")
        } catch {
            throw SkillsError.catalogFetchFailed("Anthropic catalog: \(error.localizedDescription)")
        }

        let index = CatalogIndex(
            version: Self.catalogVersion,
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            skills: catalogSkills
        )

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheDir.appendingPathComponent("catalog-index.json"), options: .atomic)

        catalogCache = index
        return await mergeInstalledState(mapCatalog(index))
    }
}

extension DefaultSkillsService {
    struct SkillTarget {
        let id: String
        let skillsDirectory: String
    }

    private var sharedDiscoveryTargets: [SkillTarget] {
        sharedSkillsDirectories.map { directory in
            SkillTarget(id: "shared-agent-skills", skillsDirectory: directory)
        }
    }

    var syncTargets: [SkillTarget] {
        agentRegistry.agents.compactMap { agent in
            guard let skillsDirectory = agent.skillsDirectory else {
                return nil
            }
            return SkillTarget(id: agent.id, skillsDirectory: skillsDirectory)
        }
    }

    var discoveryTargets: [SkillTarget] {
        sharedDiscoveryTargets
            + syncTargets
            + [SkillTarget(id: "legacy-agent", skillsDirectory: "~/.agent/skills")]
    }

    func scanDirectory(_ directory: URL, seenIDs: inout Set<String>) -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        return entries.compactMap { entry in
            let skillFile = entry.appendingPathComponent("SKILL.md")
            let skillID = entry.lastPathComponent
            guard !seenIDs.contains(skillID),
                  FileManager.default.fileExists(atPath: skillFile.path),
                  let content = try? String(contentsOf: skillFile, encoding: .utf8) else {
                return nil
            }

            seenIDs.insert(skillID)
            let frontmatter = Self.parseFrontmatter(content)
            return Skill(
                id: skillID,
                name: frontmatter.name ?? skillID,
                description: frontmatter.description ?? "",
                version: frontmatter.version,
                source: .local,
                isInstalled: true,
                syncedAgentIDs: syncedAgentIDs(for: skillID),
                owner: nil,
                repo: nil,
                sourceUrl: nil,
                installs: nil
            )
        }
    }

    func loadLocalSkillMarkdownDocument(skillID: String) -> SkillMarkdownDocument? {
        let candidateDirectories = [baseDir] + discoveryTargets.map {
            URL(fileURLWithPath: ($0.skillsDirectory as NSString).expandingTildeInPath)
        }

        for directory in candidateDirectories {
            let skillFile = directory
                .appendingPathComponent(skillID, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillFile.path),
                  let content = try? String(contentsOf: skillFile, encoding: .utf8),
                  !content.isEmpty else {
                continue
            }
            return SkillMarkdownDocument(
                markdown: content,
                baseURL: skillFile.deletingLastPathComponent(),
                browserURL: nil
            )
        }

        return nil
    }

    func syncedAgentIDs(for skillID: String) -> [String] {
        syncTargets.compactMap { target in
            let link = URL(fileURLWithPath: (target.skillsDirectory as NSString).expandingTildeInPath)
                .appendingPathComponent(skillID)
            return FileManager.default.fileExists(atPath: link.path) ? target.id : nil
        }
        .sorted()
    }

    func detectedAgents() -> [String] {
        syncTargets.compactMap { target in
            let path = (target.skillsDirectory as NSString).expandingTildeInPath
            let parentDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
            return FileManager.default.fileExists(atPath: parentDirectory) ? target.id : nil
        }
    }

    func sync(skillID: String, to agentIDs: [String]) {
        let sourceDirectory = baseDir.appendingPathComponent(skillID, isDirectory: true)

        for agentID in agentIDs {
            guard let target = syncTargets.first(where: { $0.id == agentID }) else {
                continue
            }

            let skillsDirectory = URL(fileURLWithPath: (target.skillsDirectory as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true, attributes: nil)
            let link = skillsDirectory.appendingPathComponent(skillID)
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: sourceDirectory)
        }
    }

    func mapCatalog(_ index: CatalogIndex) -> [Skill] {
        sortSkills(index.skills.map { entry in
            Skill(
                id: entry.id,
                name: entry.name,
                description: entry.description,
                version: nil,
                source: entry.source == "skillsSh" ? .skillsSh : .catalog,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: entry.owner,
                repo: entry.repo,
                sourceUrl: entry.sourceUrl,
                installs: nil
            )
        })
    }

    func mergeInstalledState(_ catalog: [Skill]) async -> [Skill] {
        let installed = (try? await loadInstalled()) ?? []
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        var merged = catalog.map { skill in
            var mergedSkill = skill
            if let installedSkill = installedByID[skill.id] {
                mergedSkill.isInstalled = true
                mergedSkill.syncedAgentIDs = installedSkill.syncedAgentIDs
            }
            return mergedSkill
        }

        for skill in installed where !merged.contains(where: { $0.id == skill.id }) {
            merged.append(skill)
        }

        return sortSkills(merged)
    }

    func loadBundledCatalog() -> CatalogIndex? {
        guard let url = bundle.url(forResource: "skills-catalog-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(CatalogIndex.self, from: data),
              index.version == Self.catalogVersion else {
            return nil
        }

        return index
    }

    func defaultBranch(owner: String, repo: String) async throws -> String {
        let cacheKey = "\(owner)/\(repo)"
        if let cached = defaultBranchCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < Self.repoCacheTTL {
            return cached.branch
        }

        guard let url = Self.makeGitHubRepoAPIURL(owner: owner, repo: repo) else {
            return "main"
        }

        var request = URLRequest(url: url)
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let branch = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["default_branch"] as? String ?? "main"
        defaultBranchCache[cacheKey] = (branch, Date())
        return branch
    }

    func fetchGitHubTree(owner: String, repo: String, branch: String) async throws -> [GitTreeEntry] {
        let cacheKey = "\(owner)/\(repo)#\(branch)"
        if let cached = treeCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < Self.repoCacheTTL {
            return cached.entries
        }

        guard let url = Self.makeGitHubTreeAPIURL(owner: owner, repo: repo, branch: branch) else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let entries = try JSONDecoder().decode(GitTreeResponse.self, from: data).tree
        treeCache[cacheKey] = (entries, Date())
        return entries
    }

    func downloadRawSkillMd(owner: String, repo: String, branch: String, path: String) async throws -> SkillMarkdownDocument {
        guard let url = Self.makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: path) else {
            throw SkillsError.noSource(path)
        }

        let browserURL = Self.makeGitHubBlobBrowserURL(owner: owner, repo: repo, branch: branch, path: path)

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else {
            throw SkillsError.noSource(path)
        }

        return SkillMarkdownDocument(
            markdown: content,
            baseURL: url.deletingLastPathComponent(),
            browserURL: browserURL
        )
    }

    func fetchCatalogRepo(owner: String, repo: String) async throws -> [CatalogSkillEntry] {
        let branch = try await defaultBranch(owner: owner, repo: repo)
        let treeEntries = try await fetchGitHubTree(owner: owner, repo: repo, branch: branch)
        let fetchedEntries = try await Self.fetchCatalogEntries(
            owner: owner,
            repo: repo,
            branch: branch,
            treeEntries: treeEntries,
            session: session
        )
        return Self.deduplicateCatalogEntries(fetchedEntries)
    }

    func sortSkills(_ skills: [Skill]) -> [Skill] {
        skills.sorted {
            let lhsKey = $0.name.lowercased()
            let rhsKey = $1.name.lowercased()
            return lhsKey == rhsKey ? $0.id < $1.id : lhsKey < rhsKey
        }
    }
}

private extension DefaultSkillsService {
    func fetchTreeDiscoveredSkillMarkdown(
        owner: String,
        repo: String,
        branch: String,
        skill: Skill
    ) async throws -> SkillMarkdownDocument? {
        guard let treeEntries = try? await fetchGitHubTree(owner: owner, repo: repo, branch: branch) else {
            return nil
        }

        let skillPaths = treeEntries
            .filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }
            .map(\.path)

        if skillPaths.count == 1,
           let directMatch = skillPaths.first,
           let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: directMatch) {
            return content
        }

        if let directoryMatch = skillPaths.first(where: { $0.contains("/\(skill.id)/") }),
           let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: directoryMatch) {
            return content
        }

        for path in skillPaths {
            guard let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: path) else {
                continue
            }

            let frontmatter = Self.parseFrontmatter(content.markdown)
            if frontmatter.name == skill.id || frontmatter.name == skill.name {
                return content
            }
        }

        guard let fallbackPath = skillPaths.first else {
            return nil
        }

        return try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: fallbackPath)
    }
}
