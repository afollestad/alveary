import Foundation

extension DefaultSkillsService {
    struct CatalogIndex: Codable, Equatable {
        let version: Int
        let lastUpdated: String
        let skills: [CatalogSkillEntry]
    }

    struct CatalogSkillEntry: Codable, Equatable {
        let id: String
        let name: String
        let description: String
        let argumentHint: String?
        let source: String
        let owner: String?
        let repo: String?
        let sourceUrl: String?
    }

    struct GitTreeEntry: Decodable, Equatable {
        let path: String
        let type: String
    }

    struct SkillFrontmatter {
        let name: String?
        let description: String?
        let argumentHint: String?
        let version: String?
    }

    static func markdownBody(from content: String) -> String {
        guard let frontmatter = frontmatterSections(in: content) else {
            return content
        }

        return String(frontmatter.body.drop(while: { $0.isNewline }))
    }

    static func parseFrontmatter(_ content: String) -> SkillFrontmatter {
        guard let frontmatter = frontmatterSections(in: content) else {
            return SkillFrontmatter(name: nil, description: nil, argumentHint: nil, version: nil)
        }

        return SkillFrontmatter(
            name: extractYamlValue(from: frontmatter.yaml, key: "name"),
            description: extractYamlValue(from: frontmatter.yaml, key: "description"),
            argumentHint: extractYamlValue(from: frontmatter.yaml, key: "argument-hint")
                ?? extractYamlValue(from: frontmatter.yaml, key: "argumentHint"),
            version: extractYamlValue(from: frontmatter.yaml, key: "version")
        )
    }

    static func makeGitHubRepoAPIURL(owner: String, repo: String) -> URL? {
        let encodedOwner = encodeGitHubPathComponent(owner)
        let encodedRepo = encodeGitHubPathComponent(repo)
        return URL(string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)")
    }

    static func makeGitHubRawURL(owner: String, repo: String, branch: String, path: String) -> URL? {
        let encodedOwner = encodeGitHubPathComponent(owner)
        let encodedRepo = encodeGitHubPathComponent(repo)
        let encodedBranch = encodeGitHubPathComponent(branch)
        let encodedPath = encodeGitHubRelativePath(path)
        return URL(
            string: "https://raw.githubusercontent.com/\(encodedOwner)/\(encodedRepo)/\(encodedBranch)/\(encodedPath)"
        )
    }

    static func makeGitHubTreeAPIURL(owner: String, repo: String, branch: String) -> URL? {
        let encodedOwner = encodeGitHubPathComponent(owner)
        let encodedRepo = encodeGitHubPathComponent(repo)
        let encodedBranch = encodeGitHubPathComponent(branch)
        return URL(
            string: "https://api.github.com/repos/\(encodedOwner)/\(encodedRepo)/git/trees/\(encodedBranch)?recursive=1"
        )
    }

    static func makeGitHubBlobBrowserURL(owner: String, repo: String, branch: String, path: String) -> URL? {
        let encodedBranch = encodeGitHubPathComponent(branch)
        let encodedPath = encodeGitHubRelativePath(path)
        let suffix = encodedPath.isEmpty ? "" : "/\(encodedPath)"
        return URL(
            string: "https://github.com/\(encodeGitHubPathComponent(owner))/\(encodeGitHubPathComponent(repo))/blob/\(encodedBranch)\(suffix)"
        )
    }

    static func fetchCatalogEntries(
        owner: String,
        repo: String,
        branch: String,
        treeEntries: [GitTreeEntry],
        session: URLSession
    ) async throws -> [CatalogSkillEntry] {
        let skillEntries = treeEntries.filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }

        return try await withThrowingTaskGroup(of: CatalogSkillEntry?.self) { group in
            var results: [CatalogSkillEntry] = []
            var enqueuedCount = 0
            let maxConcurrent = 8

            for entry in skillEntries {
                if enqueuedCount >= maxConcurrent,
                   let result = try await group.next(),
                   let result {
                    results.append(result)
                }

                enqueuedCount += 1
                group.addTask {
                    try await fetchCatalogEntry(
                        owner: owner,
                        repo: repo,
                        branch: branch,
                        entry: entry,
                        session: session
                    )
                }
            }

            for try await result in group {
                if let result {
                    results.append(result)
                }
            }

            return results
        }
    }

    static func fetchFallbackSkillMarkdown(
        owner: String,
        repo: String,
        branch: String,
        skillID: String,
        session: URLSession
    ) async throws -> SkillMarkdownDocument? {
        for path in fallbackSkillMarkdownPaths(for: skillID) {
            guard let url = makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: path) else {
                continue
            }

            let browserURL = makeGitHubBlobBrowserURL(owner: owner, repo: repo, branch: branch, path: path)

            if let markdown = try await fetchMarkdownDocumentIfAvailable(at: url, browserURL: browserURL, session: session) {
                return markdown
            }
        }

        return nil
    }

    static func deduplicateCatalogEntries(_ entries: [CatalogSkillEntry]) -> [CatalogSkillEntry] {
        var seenIDs: Set<String> = []
        let deduped = entries.filter { seenIDs.insert($0.id).inserted }
        return deduped.sorted {
            let lhsKey = $0.name.lowercased()
            let rhsKey = $1.name.lowercased()
            return lhsKey == rhsKey ? $0.id < $1.id : lhsKey < rhsKey
        }
    }

    static func defaultMarkdownDocument(for skill: Skill) -> SkillMarkdownDocument {
        SkillMarkdownDocument(
            markdown: [
                "---",
                "name: \(skill.id)",
                "description: \(skill.description)",
                "---",
                "",
                "# \(skill.name)",
                "",
                skill.description
            ].joined(separator: "\n"),
            baseURL: skill.sourceUrl.flatMap(URL.init(string:)),
            browserURL: skill.githubURL
        )
    }
}

extension DefaultSkillsService {
    struct GitTreeResponse: Decodable {
        let tree: [GitTreeEntry]
    }

    struct SkillsShResponse: Decodable {
        let skills: [SkillsShEntry]
    }

    struct SkillsShEntry: Decodable {
        let skillId: String
        let name: String
        let source: String
        let installs: Int
    }
}

private extension DefaultSkillsService {
    static func fetchMarkdownDocumentIfAvailable(
        at url: URL,
        browserURL: URL?,
        session: URLSession
    ) async throws -> SkillMarkdownDocument? {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let content = String(data: data, encoding: .utf8),
              !content.isEmpty else {
            return nil
        }

        return SkillMarkdownDocument(
            markdown: content,
            baseURL: url.deletingLastPathComponent(),
            browserURL: browserURL
        )
    }

    static func fallbackSkillMarkdownPaths(for skillID: String) -> [String] {
        [
            "skills/\(skillID)/SKILL.md",
            "SKILL.md",
            "\(skillID)/SKILL.md",
            ".claude/skills/\(skillID)/SKILL.md"
        ]
    }

    static func fetchCatalogEntry(
        owner: String,
        repo: String,
        branch: String,
        entry: GitTreeEntry,
        session: URLSession
    ) async throws -> CatalogSkillEntry? {
        guard let url = makeGitHubRawURL(owner: owner, repo: repo, branch: branch, path: entry.path) else {
            return nil
        }

        let (data, _) = try await session.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let frontmatter = parseFrontmatter(content)
        let pathComponents = entry.path.split(separator: "/")
        let skillID = pathComponents.dropLast().last.map(String.init) ?? entry.path
        return CatalogSkillEntry(
            id: skillID,
            name: frontmatter.name ?? skillID,
            description: frontmatter.description ?? "",
            argumentHint: frontmatter.argumentHint,
            source: "catalog",
            owner: owner,
            repo: repo,
            sourceUrl: makeGitHubBlobBrowserURL(
                owner: owner,
                repo: repo,
                branch: branch,
                path: entry.path
            )?.absoluteString
        )
    }

    static func frontmatterSections(in content: String) -> (yaml: String, body: Substring)? {
        guard content.hasPrefix("---") else {
            return nil
        }

        let yamlStart = content.index(content.startIndex, offsetBy: 3)
        guard let closingRange = content.range(of: "\n---", range: yamlStart..<content.endIndex) else {
            return nil
        }

        return (
            yaml: String(content[yamlStart..<closingRange.lowerBound]),
            body: content[closingRange.upperBound..<content.endIndex]
        )
    }

    static func extractYamlValue(from yaml: String, key: String) -> String? {
        let prefix = "\(key):"
        let lines = yaml.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix(prefix) else {
                continue
            }

            var value = trimmedLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let scalarStyle = value.first, scalarStyle == "|" || scalarStyle == ">" {
                let blockLines = yamlBlockLines(
                    in: lines,
                    after: index,
                    parentIndentation: indentation(of: line)
                )
                let blockValue = scalarStyle == "|"
                    ? blockLines.joined(separator: "\n")
                    : foldedYamlBlockValue(from: blockLines)
                return blockValue.isEmpty ? nil : blockValue
            }

            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }

        return nil
    }

    static func yamlBlockLines(
        in lines: [String],
        after startIndex: Int,
        parentIndentation: Int
    ) -> [String] {
        guard startIndex + 1 < lines.count else {
            return []
        }

        var values: [String] = []
        var blockIndentation: Int?

        for line in lines[(startIndex + 1)...] {
            let lineIndentation = indentation(of: line)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                guard blockIndentation != nil else {
                    continue
                }
                values.append("")
                continue
            }

            guard lineIndentation > parentIndentation else {
                break
            }

            if blockIndentation == nil {
                blockIndentation = lineIndentation
            }

            let contentIndentation = blockIndentation ?? lineIndentation
            let trimCount = min(contentIndentation, line.count)
            values.append(String(line.dropFirst(trimCount)))
        }

        return values
    }

    static func foldedYamlBlockValue(from lines: [String]) -> String {
        var result = ""

        for line in lines {
            if line.isEmpty {
                result += result.hasSuffix("\n") || result.isEmpty ? "\n" : "\n\n"
                continue
            }

            if result.isEmpty || result.hasSuffix("\n") {
                result += line
            } else {
                result += " " + line
            }
        }

        return result
    }

    static func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    static func encodeGitHubPathComponent(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: gitHubPathComponentAllowed) ?? component
    }

    static func encodeGitHubRelativePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeGitHubPathComponent(String($0)) }
            .joined(separator: "/")
    }
}

private let gitHubPathComponentAllowed = CharacterSet.urlPathAllowed
    .subtracting(CharacterSet(charactersIn: "/"))
