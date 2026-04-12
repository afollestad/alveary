import XCTest

@testable import Alveary

actor SnapshotSkillsService: SkillsService {
    func loadInstalled() async throws -> [Skill] {
        [
            Skill(
                id: "skill-ios-accessibility",
                name: "ios-accessibility",
                description: "Audit SwiftUI screens for VoiceOver and Dynamic Type issues.",
                version: "1.4.0",
                source: .local,
                isInstalled: true,
                syncedAgentIDs: ["claude"],
                owner: "squareup",
                repo: "agents",
                sourceUrl: "https://example.com/ios-accessibility",
                installs: nil
            )
        ]
    }

    func loadCatalog() async throws -> [Skill] {
        [
            Skill(
                id: "skill-walkthrough",
                name: "walkthrough",
                description: "Explain architecture and visualize code paths for a feature area.",
                version: "2.0.1",
                source: .catalog,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: "squareup",
                repo: "agents",
                sourceUrl: "https://example.com/walkthrough",
                installs: 1_284
            )
        ]
    }

    func searchSkillsSh(query: String) async throws -> [Skill] {
        [
            Skill(
                id: "skill-ui-snapshots",
                name: "ui-snapshots",
                description: "Generate snapshot tests for macOS SwiftUI screens.",
                version: "0.9.0",
                source: .skillsSh,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: "community",
                repo: "skills",
                sourceUrl: "https://example.com/ui-snapshots",
                installs: 312
            )
        ]
    }

    func fetchSkillMd(skill: Skill) async throws -> SkillMarkdownDocument {
        SkillMarkdownDocument(
            markdown: "# \(skill.name)\n\n\(skill.description)",
            baseURL: skill.sourceUrl.flatMap(URL.init(string:))
        )
    }

    func install(_ skill: Skill) async throws {}

    func uninstall(_ skill: Skill) async throws {}

    func create(name: String, description: String, instructions: String) async throws {}

    func refreshCatalog() async throws -> [Skill] {
        try await loadCatalog()
    }
}

@MainActor
final class SnapshotMCPService: MCPService {
    func loadAll() async throws -> [MCPServer] {
        [
            MCPServer(
                name: "context7",
                transport: .http,
                command: nil,
                args: nil,
                url: "https://mcp.context7.com/mcp",
                headers: ["Authorization": "Bearer ***"],
                env: nil,
                providers: ["claude"]
            )
        ]
    }

    func loadRecommended() async throws -> [RecommendedMCPServer] {
        [
            RecommendedMCPServer(
                template: MCPServer(
                    name: "playwright",
                    transport: .stdio,
                    command: "npx",
                    args: ["-y", "@anthropic/mcp-playwright"],
                    url: nil,
                    headers: nil,
                    env: ["PLAYWRIGHT_BROWSERS_PATH": "0"],
                    providers: []
                ),
                description: "Browser automation for UI validation and screenshot capture.",
                headerPrompts: ["PLAYWRIGHT_TOKEN"]
            )
        ]
    }

    func addServer(_ server: MCPServer, for agents: [String]) async throws {}

    func removeServer(_ server: MCPServer) async throws {}

    func availableAgents() async -> [MCPAgentAvailability] {
        [
            MCPAgentAvailability(agentId: "claude", name: "Claude Code", supportedTransports: [.stdio, .http]),
            MCPAgentAvailability(agentId: "amp", name: "Amp", supportedTransports: [.http])
        ]
    }
}
