import Foundation

struct SkillMarkdownDocument: Sendable, Equatable {
    let markdown: String
    let baseURL: URL?
}

protocol SkillsService: Actor {
    func loadInstalled() async throws -> [Skill]
    func loadCatalog() async throws -> [Skill]
    func searchSkillsSh(query: String) async throws -> [Skill]
    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument
    func install(_ skill: Skill) async throws
    func uninstall(_ skill: Skill) async throws
    func create(name: String, description: String, instructions: String) async throws
    @discardableResult
    func refreshCatalog() async throws -> [Skill]
}

enum SkillsError: Error, Sendable, Equatable {
    case invalidName(String)
    case noSource(String)
    case catalogFetchFailed(String)
}

extension SkillsError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid skill name: \(name)"
        case .noSource(let skillID):
            return "Unable to resolve source content for skill \(skillID)"
        case .catalogFetchFailed(let message):
            return message
        }
    }
}
