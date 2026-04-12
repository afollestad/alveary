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
    let version: String?
    let source: Source
    var isInstalled: Bool
    var syncedAgentIDs: [String]
    let owner: String?
    let repo: String?
    let sourceUrl: String?
    let installs: Int?

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
