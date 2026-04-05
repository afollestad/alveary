# Part 3f: Skills Service

`DefaultSkillsService` concrete implementation, `SkillsError`, and unit tests. Continues from Part 3e.

### Concrete Implementation

```swift
actor DefaultSkillsService: SkillsService {  // Skep/Services/Skills/DefaultSkillsService.swift
    private let baseDir: URL           // ~/.agentskills/
    private let cacheDir: URL          // ~/.agentskills/.skep/
    private let session: URLSession    // Injected for testability (default: .shared)
    private let bundle: Bundle         // For bundled catalog fallback on offline first run
    private let agentRegistry: AgentRegistry
    private var catalogCache: CatalogIndex?
    private var defaultBranchCache: [String: (branch: String, fetchedAt: Date)] = [:]
    private var treeCache: [String: (entries: [GitTreeEntry], fetchedAt: Date)] = [:]
    private static let catalogVersion = 1
    private static let repoCacheTTL: TimeInterval = 600  // 10 minutes

    /// Skill directories from the shared `AgentRegistry`, plus the legacy path kept
    /// for discovery/back-compat. SkillsService should not maintain a second agent list.
    private var skillTargets: [(id: String, skillsDir: String)] {
        let registered = agentRegistry.agents.compactMap { agent -> (String, String)? in
            guard let skillsDir = agent.skillsDirectory else { return nil }
            return (agent.id, skillsDir)
        }
        return registered + [("legacy-agent", "~/.agent/skills")]
    }

    struct CatalogIndex: Codable {
        let version: Int
        let lastUpdated: String
        var skills: [CatalogSkillEntry]
    }
    struct CatalogSkillEntry: Codable {
        let id: String
        let name: String
        let description: String
        let source: String       // "catalog" or "skillsSh"
        let owner: String?
        let repo: String?
        let sourceUrl: String?   // Browser-facing GitHub tree URL for "View on GitHub"
    }

    init(baseDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agentskills"),
         session: URLSession = .shared,
         bundle: Bundle = .main,
         agentRegistry: AgentRegistry) {
        self.baseDir = baseDir
        self.cacheDir = baseDir.appendingPathComponent(".skep")
        self.session = session
        self.bundle = bundle
        self.agentRegistry = agentRegistry
    }

    // MARK: - Load Installed

    func loadInstalled() async throws -> [Skill] {
        var skills: [Skill] = []
        var seenIds: Set<String> = []

        // Scan central location
        skills += scanDirectory(baseDir, seenIds: &seenIds)

        // Scan external agent directories for skills not installed through the app
        for target in skillTargets {
            let dir = URL(fileURLWithPath: (target.skillsDir as NSString).expandingTildeInPath)
            skills += scanDirectory(dir, seenIds: &seenIds)
        }
        return skills
    }

    /// Reports which registered agent skill directories currently contain this skill.
    /// This lets the UI surface partial sync drift instead of collapsing everything into
    /// a single `isInstalled` boolean.
    private func syncedAgentIDs(for skillID: String) -> [String] {
        skillTargets.compactMap { target in
            let path = URL(fileURLWithPath: (target.skillsDir as NSString).expandingTildeInPath)
                .appendingPathComponent(skillID)
                .path
            return FileManager.default.fileExists(atPath: path) ? target.id : nil
        }
        .sorted()
    }

    private func scanDirectory(_ dir: URL, seenIds: inout Set<String>) -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries.compactMap { entry in
            let skillMd = entry.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillMd.path),
                  let content = try? String(contentsOf: skillMd),
                  !seenIds.contains(entry.lastPathComponent) else { return nil }
            let id = entry.lastPathComponent
            seenIds.insert(id)
            let (name, description, version) = Self.parseFrontmatter(content)
            return Skill(
                id: id, name: name ?? id, description: description ?? "",
                version: version, source: .local, isInstalled: true,
                syncedAgentIDs: syncedAgentIDs(for: id),
                owner: nil, repo: nil, sourceUrl: nil, installs: nil
            )
        }
    }

    // MARK: - Catalog

    func loadCatalog() async throws -> [Skill] {
        if let cached = catalogCache { return await mergeInstalledState(mapCatalog(cached)) }

        // Try disk cache
        let cacheFile = cacheDir.appendingPathComponent("catalog-index.json")
        if let data = try? Data(contentsOf: cacheFile),
           let index = try? JSONDecoder().decode(CatalogIndex.self, from: data),
           index.version == Self.catalogVersion {
            catalogCache = index
            return await mergeInstalledState(mapCatalog(index))
        }

        // No cache — prefer a live fetch, but fall back to the bundled snapshot so
        // first-run/offline users still see a non-empty recommended catalog.
        do {
            return try await refreshCatalog()
        } catch {
            guard let bundled = loadBundledCatalog() else { throw error }
            catalogCache = bundled
            return await mergeInstalledState(mapCatalog(bundled))
        }
    }

    func refreshCatalog() async throws -> [Skill] {
        // v1 fetches from the validated Anthropic curated catalog only. If additional
        // curated sources are validated later, add them here and keep the same
        // first-occurrence-wins dedupe rule on ID collisions.
        let allSkills: [CatalogSkillEntry]
        do {
            allSkills = try await fetchCatalogRepo(owner: "anthropics", repo: "skills")
        } catch {
            throw SkillsError.catalogFetchFailed("Anthropic catalog: \(error.localizedDescription)")
        }

        let index = CatalogIndex(
            version: Self.catalogVersion,
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            skills: allSkills
        )
        // Write to disk
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheDir.appendingPathComponent("catalog-index.json"), options: .atomic)

        catalogCache = index
        return await mergeInstalledState(mapCatalog(index))
    }

    // MARK: - skills.sh Search

    func searchSkillsSh(query: String) async throws -> [Skill] {
        guard query.count >= 2 else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://skills.sh/api/search?q=\(encoded)") else {
            return []  // Malformed query — skip search
        }

        var request = URLRequest(url: url)
        request.setValue("Skep", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, _) = try await session.data(for: request)
        let result = try JSONDecoder().decode(SkillsShResponse.self, from: data)

        return result.skills.map { s in
            let slashIdx = s.source.firstIndex(of: "/")
            let owner = slashIdx.map { String(s.source[s.source.startIndex..<$0]) }
            let repo = slashIdx.map { String(s.source[s.source.index(after: $0)...]) }
            return Skill(
                id: s.skillId, name: s.name, description: "",
                version: nil, source: .skillsSh, isInstalled: false,
                syncedAgentIDs: [],
                owner: owner, repo: repo, sourceUrl: nil, installs: s.installs
            )
        }
    }

    private struct SkillsShResponse: Decodable {
        let skills: [SkillsShEntry]
    }
    private struct SkillsShEntry: Decodable {
        let skillId: String
        let name: String
        let source: String
        let installs: Int
    }

    // MARK: - Fetch SKILL.md

    func fetchSkillMd(skill: Skill) async throws -> String {
        // Resolve content from structured repo metadata instead of reparsing a browser URL.
        // This keeps slash-containing branch names and encoded paths from breaking fetches.
        guard let owner = skill.owner, let repo = skill.repo else {
            throw SkillsError.noSource(skill.id)
        }
        let branch = try await defaultBranch(owner: owner, repo: repo)

        // First try common SKILL.md paths. raw.githubusercontent.com is CDN-served and
        // doesn't count against the GitHub API rate limit, so this avoids burning Trees
        // API quota when the repository follows a conventional layout.
        let fallbackPaths = [
            "skills/\(skill.id)/SKILL.md",
            "SKILL.md",
            "\(skill.id)/SKILL.md",
            ".claude/skills/\(skill.id)/SKILL.md"
        ]
        for path in fallbackPaths {
            guard let url = Self.makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: path) else {
                continue
            }
            if let (data, response) = try? await session.data(from: url),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let content = String(data: data, encoding: .utf8), !content.isEmpty {
                return content
            }
        }

        // Slow path: fallback guesses failed, so use the Trees API to discover all SKILL.md files.
        if let treeEntries = try? await fetchGitHubTree(owner: owner, repo: repo, branch: branch) {
            let skillMdPaths = treeEntries.filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }.map(\.path)

            if skillMdPaths.count == 1 {
                if let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: skillMdPaths[0]) {
                    return content
                }
            } else if let match = skillMdPaths.first(where: { $0.contains("/\(skill.id)/") }) {
                if let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: match) {
                    return content
                }
            } else {
                for path in skillMdPaths {
                    guard let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: path) else {
                        continue
                    }
                    let (name, _, _) = Self.parseFrontmatter(content)
                    if name == skill.id || name == skill.name {
                        return content
                    }
                }
                if let firstPath = skillMdPaths.first,
                   let content = try? await downloadRawSkillMd(owner: owner, repo: repo, branch: branch, path: firstPath) {
                    return content
                }
            }
        }

        // Last resort: generate a stub SKILL.md from the skill's metadata
        // so the install still succeeds (the user can edit it later).
        return "---\nname: \(skill.name)\ndescription: \(skill.description)\n---\n\n# \(skill.name)\n\n\(skill.description)\n"
    }

    private struct GitTreeResponse: Decodable {
        let tree: [GitTreeEntry]
    }
    private struct GitTreeEntry: Decodable {
        let path: String
        let type: String
    }

    /// Resolve and cache the repo's default branch so community repos are not forced onto `main`.
    private func defaultBranch(owner: String, repo: String) async throws -> String {
        let cacheKey = "\(owner)/\(repo)"
        if let cached = defaultBranchCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < Self.repoCacheTTL {
            return cached.branch
        }
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
            return "main"
        }
        var request = URLRequest(url: url)
        request.setValue("Skep", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let branch = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["default_branch"] as? String ?? "main"
        defaultBranchCache[cacheKey] = (branch, Date())
        return branch
    }

    /// Fetch the full file tree for a GitHub repo and branch.
    private func fetchGitHubTree(owner: String, repo: String, branch: String) async throws -> [GitTreeEntry] {
        let cacheKey = "\(owner)/\(repo)#\(branch)"
        if let cached = treeCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < Self.repoCacheTTL {
            return cached.entries
        }
        guard let url = Self.makeGitHubTreeAPIURL(owner: owner, repo: repo, branch: branch) else {
            return []  // Malformed owner/repo — skip
        }
        var request = URLRequest(url: url)
        request.setValue("Skep", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let entries = try JSONDecoder().decode(GitTreeResponse.self, from: data).tree
        treeCache[cacheKey] = (entries, Date())
        return entries
    }

    private func loadBundledCatalog() -> CatalogIndex? {
        guard let url = bundle.url(forResource: "skills-catalog-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(CatalogIndex.self, from: data),
              index.version == Self.catalogVersion else {
            return nil
        }
        return index
    }

    // MARK: - Install / Uninstall

    func install(_ skill: Skill) async throws {
        let content = try await fetchSkillMd(skill: skill)
        let skillDir = baseDir.appendingPathComponent(skill.id)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true, attributes: nil)
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        sync(skill: skill, to: detectedAgents())
        catalogCache = nil  // Force re-merge of installed state
    }

    func uninstall(_ skill: Skill) async throws {
        // Remove from central location
        let skillDir = baseDir.appendingPathComponent(skill.id)
        try? FileManager.default.removeItem(at: skillDir)
        // Remove symlinks from all agents
        for target in skillTargets {
            let link = URL(fileURLWithPath: (target.skillsDir as NSString).expandingTildeInPath)
                .appendingPathComponent(skill.id)
            try? FileManager.default.removeItem(at: link)
        }
        catalogCache = nil
    }

    func create(name: String, description: String, instructions: String) async throws {
        let pattern = "^[a-z0-9]" +
            "([a-z0-9-]{0,62}[a-z0-9])?$"
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw SkillsError.invalidName(name)
        }
        // Build content without indentation — YAML top-level keys must start at column 0.
        let content = [
            "---",
            "name: \"\(name.replacingOccurrences(of: "\"", with: "\\\""))\"",
            "description: \"\(description.replacingOccurrences(of: "\"", with: "\\\""))\"",
            "version: 1.0.0",
            "---",
            "",
            instructions
        ].joined(separator: "\n")
        let skillDir = baseDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true, attributes: nil)
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let skill = Skill(
            id: name, name: name, description: description,
            version: "1.0.0", source: .local, isInstalled: true,
            syncedAgentIDs: detectedAgents(),
            owner: nil, repo: nil, sourceUrl: nil, installs: nil
        )
        sync(skill: skill, to: detectedAgents())
        catalogCache = nil
    }

    /// Symlink a skill into each detected agent's skills directory.
    /// Best-effort per agent — if one agent's symlink fails, the loop continues.
    /// Private — only called by `install()` and `create()` internally.
    private func sync(skill: Skill, to agents: [String]) {
        let source = baseDir.appendingPathComponent(skill.id)
        for agent in agents {
            guard let target = skillTargets.first(where: { $0.id == agent }) else { continue }
            let agentSkillsDir = URL(fileURLWithPath: (target.skillsDir as NSString).expandingTildeInPath)
            try? FileManager.default.createDirectory(at: agentSkillsDir, withIntermediateDirectories: true, attributes: nil)
            let link = agentSkillsDir.appendingPathComponent(skill.id)
            try? FileManager.default.removeItem(at: link)  // Remove stale symlink
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        }
    }

    // MARK: - Helpers

    private func detectedAgents() -> [String] {
        skillTargets.filter { target in
            let dir = (target.skillsDir as NSString).expandingTildeInPath
            let parent = URL(fileURLWithPath: dir).deletingLastPathComponent().path
            return FileManager.default.fileExists(atPath: parent)
        }.map(\.id)
    }

    private func downloadRawSkillMd(owner: String, repo: String, branch: String, path: String) async throws -> String {
        guard let url = Self.makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: path) else {
            throw SkillsError.noSource(path)
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            throw SkillsError.noSource(path)
        }
        return content
    }

    /// Parse YAML frontmatter between `---` delimiters for name, description, version.
    private static func parseFrontmatter(_ content: String) -> (name: String?, description: String?, version: String?) {
        guard content.hasPrefix("---") else { return (nil, nil, nil) }
        guard let closingRange = content.range(of: "\n---", range: content.index(content.startIndex, offsetBy: 3)..<content.endIndex) else {
            return (nil, nil, nil)
        }
        let yamlStart = content.index(content.startIndex, offsetBy: 3) // skip opening "---"
        let yaml = String(content[yamlStart..<closingRange.lowerBound])
        let name = extractYamlValue(from: yaml, key: "name")
        let desc = extractYamlValue(from: yaml, key: "description")
        let ver = extractYamlValue(from: yaml, key: "version")
        return (name, desc, ver)
    }

    /// Extract a simple `key: value` from a YAML string (single-line values only).
    /// Strips surrounding single or double quotes from the value.
    private static func extractYamlValue(from yaml: String, key: String) -> String? {
        let prefix = "\(key):"
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                var value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes: "value" -> value, 'value' -> value
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func mapCatalog(_ index: CatalogIndex) -> [Skill] {
        index.skills.map { s in
            Skill(
                id: s.id, name: s.name, description: s.description,
                version: nil, source: s.source == "skillsSh" ? .skillsSh : .catalog,
                isInstalled: false, syncedAgentIDs: [], owner: s.owner, repo: s.repo,
                sourceUrl: s.sourceUrl, installs: nil
            )
        }
    }

    /// Merges installed state into catalog skills.
    private func mergeInstalledState(_ catalog: [Skill]) async -> [Skill] {
        let installed = (try? await loadInstalled()) ?? []
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        var merged = catalog.map { skill in
            var s = skill
            if let installed = installedByID[s.id] {
                s.isInstalled = true
                s.syncedAgentIDs = installed.syncedAgentIDs
            }
            return s
        }
        // Append local-only skills not in the catalog
        for skill in installed where !merged.contains(where: { $0.id == skill.id }) {
            merged.append(skill)
        }
        return merged
    }

    private static let gitHubPathComponentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))

    private static func encodeGitHubPathComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: gitHubPathComponentAllowed) ?? component
    }

    private static func encodeGitHubRelativePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeGitHubPathComponent(String($0)) }
            .joined(separator: "/")
    }

    private static func makeGitHubRawURL(owner: String, repo: String, branch: String, path: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/\(encodeGitHubPathComponent(owner))/\(encodeGitHubPathComponent(repo))/\(encodeGitHubPathComponent(branch))/\(encodeGitHubRelativePath(path))")
    }

    private static func makeGitHubTreeAPIURL(owner: String, repo: String, branch: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(encodeGitHubPathComponent(owner))/\(encodeGitHubPathComponent(repo))/git/trees/\(encodeGitHubPathComponent(branch))?recursive=1")
    }

    private static func makeGitHubTreeBrowserURL(owner: String, repo: String, branch: String, path: String) -> URL? {
        URL(string: "https://github.com/\(encodeGitHubPathComponent(owner))/\(encodeGitHubPathComponent(repo))/tree/\(encodeGitHubPathComponent(branch))/\(encodeGitHubRelativePath(path))")
    }

    private func fetchCatalogRepo(owner: String, repo: String) async throws -> [CatalogSkillEntry] {
        let branch = try await defaultBranch(owner: owner, repo: repo)
        let treeEntries = try await fetchGitHubTree(owner: owner, repo: repo, branch: branch)
        let session = self.session

        let skillPaths = treeEntries.filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }
        // Limit concurrency to 8 parallel fetches.
        return try await withThrowingTaskGroup(of: CatalogSkillEntry?.self) { group in
            var results: [CatalogSkillEntry] = []
            var enqueued = 0
            let maxConcurrent = 8

            for entry in skillPaths {
                if enqueued >= maxConcurrent {
                    if let result = try await group.next() {
                        if let s = result { results.append(s) }
                    }
                }
                enqueued += 1
                group.addTask {
                    guard let url = Self.makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: entry.path) else {
                        return nil
                    }
                    let (data, _) = try await session.data(from: url)
                    guard let content = String(data: data, encoding: .utf8) else { return nil }
                    let (name, desc, _) = Self.parseFrontmatter(content)
                    let components = entry.path.split(separator: "/")
                    let dirName = components.dropLast().last.map(String.init) ?? entry.path
                    let repoRelativeDir = components.dropLast().joined(separator: "/")
                    return CatalogSkillEntry(
                        id: dirName, name: name ?? dirName, description: desc ?? "",
                        source: "catalog", owner: owner, repo: repo,
                        sourceUrl: Self.makeGitHubTreeBrowserURL(
                            owner: owner,
                            repo: repo,
                            branch: branch,
                            path: repoRelativeDir
                        )?.absoluteString
                    )
                }
            }
            // Drain remaining tasks
            for try await result in group {
                if let s = result { results.append(s) }
            }
            return results
        }
    }
}

enum SkillsError: Error, Sendable {  // Skep/Services/Skills/SkillsService.swift
    case invalidName(String)
    case noSource(String)
    case catalogFetchFailed(String)  // Curated catalog fetch failed (e.g. GitHub rate limit)
}
```

**Unit tests for SkillsService** (use temp directories for `~/.agentskills/`, agent skill dirs, and a stub `AgentRegistry`): cover all public methods and `parseFrontmatter` with standard happy-path and error tests. Non-obvious:
- `loadInstalled()` deduplicates across central and external agent directories (same skill ID in both)
- `fetchSkillMd()` resolves the repo default branch instead of assuming `main`
- `parseFrontmatter()` strips surrounding double quotes (`name: "my-skill"` -> `my-skill`) and single quotes separately
- `parseFrontmatter()` preserves unquoted values as-is (`version: 1.0.0` -> `1.0.0`)
- `fetchSkillMd()` matches by directory name first, then by frontmatter `name` when multiple `SKILL.md` files exist in the repo
- `fetchSkillMd()` falls back to common paths when Trees API fails (rate-limit scenario)
- `fetchSkillMd()` returns cached repo metadata/tree on second call for the same `owner/repo` within TTL
- GitHub raw/tree URL construction percent-encodes slash-containing branch names instead of assuming `main`
- `fetchCatalogRepo()` snapshots actor-owned helpers before `group.addTask`, so the task-group path stays valid under Swift 6 actor isolation rules
- `create()` rejects invalid names (uppercase, spaces, special chars, empty, >64 chars)
- `create()` escapes double quotes inside name/description in generated YAML frontmatter
- `skillTargets` are derived from `AgentRegistry.skillsDirectory`; adding a new sync-capable agent requires only a registry entry, not a second service-local list edit
- `install()` and `create()` symlink to agents whose config directories exist, skip others (via internal `sync()`)
- `loadCatalog()` still merges installed state when serving from the in-memory `catalogCache`
- `loadCatalog()` falls back to the bundled `skills-catalog-fallback.json` snapshot when no version-matching disk cache exists and the live catalog fetch fails
- `refreshCatalog()` throws `catalogFetchFailed` when the curated catalog fetch fails (e.g. rate limit)
- `refreshCatalog()` always performs a real refresh when explicitly invoked; only ordinary reads (`loadCatalog()`) prefer cache
- `fetchSkillMd()` treats non-200 raw GitHub responses as missing content, so the UI/install path uses the synthesized fallback instead of rendering `404: Not Found`
- `loadInstalled()` and catalog merges preserve `syncedAgentIDs`, so a skill can be installed centrally but visibly drifted or only partially linked across detected agents
