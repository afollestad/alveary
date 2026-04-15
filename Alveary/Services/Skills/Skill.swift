import Foundation

struct Skill: Identifiable, Sendable, Equatable {
    enum Source: String, Sendable, Equatable {
        case local
        case catalog
        case skillsSh
    }

    let id: String
    let name: String
    let description: String
    let argumentHint: String?
    let version: String?
    let source: Source
    var isInstalled: Bool
    var syncedAgentIDs: [String]
    let owner: String?
    let repo: String?
    let sourceUrl: String?
    let installs: Int?

    init(
        id: String,
        name: String,
        description: String,
        argumentHint: String? = nil,
        version: String?,
        source: Source,
        isInstalled: Bool,
        syncedAgentIDs: [String],
        owner: String?,
        repo: String?,
        sourceUrl: String?,
        installs: Int?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.version = version
        self.source = source
        self.isInstalled = isInstalled
        self.syncedAgentIDs = syncedAgentIDs
        self.owner = owner
        self.repo = repo
        self.sourceUrl = sourceUrl
        self.installs = installs
    }

    var githubURL: URL? {
        if let sourceUrl, let url = URL(string: sourceUrl) {
            return url
        }

        guard let owner, let repo else {
            return nil
        }

        return URL(string: "https://github.com/\(owner)/\(repo)")
    }
}
