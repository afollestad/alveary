import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class MCPServiceTests: XCTestCase {
    func testAddServerWritesClaudeConfigAndRemovesDeselectedAgents() async throws {
        let fixture = try MCPServiceFixture()
        defer { fixture.cleanup() }
        try await fixture.writeCodexServers([
            "context7": ["command": "npx", "args": ["serve"]]
        ])
        try fixture.writeTrustedProjects()

        let server = MCPServer(
            name: "context7",
            transport: .http,
            command: nil,
            args: nil,
            url: "https://mcp.context7.com/mcp",
            headers: ["X-API-KEY": "secret"],
            env: nil,
            providers: []
        )

        try await fixture.service.addServer(server, for: ["claude"])

        let claudeServers = try await fixture.claudeStore.readMCPServers()
        let codexServers = try await fixture.codexStore.readMCPServers()
        let root = try fixture.readClaudeRoot()

        XCTAssertEqual(claudeServers["context7"]?.url, "https://mcp.context7.com/mcp")
        XCTAssertEqual(claudeServers["context7"]?.headers?["X-API-KEY"], "secret")
        XCTAssertNil(codexServers["context7"])
        XCTAssertNotNil(root["projects"])
    }

    func testLoadAllDeduplicatesProvidersByServerName() async throws {
        let fixture = try MCPServiceFixture()
        defer { fixture.cleanup() }
        try await fixture.claudeStore.writeMCPServers([
            "filesystem": AgentCLIKit.ClaudeMCPServerConfig(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem"],
                url: nil,
                headers: nil,
                env: nil
            )
        ])
        try await fixture.writeCodexServers([
            "filesystem": [
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem"]
            ]
        ])

        let servers = try await fixture.service.loadAll()

        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.name, "filesystem")
        XCTAssertEqual(servers.first?.providers, ["claude", "codex"])
    }

    func testLoadRecommendedPreservesHeaderPromptsAndExcludesInstalledServers() async throws {
        let fixture = try MCPServiceFixture()
        defer { fixture.cleanup() }

        let firstLoad = try await fixture.service.loadRecommended()
        XCTAssertEqual(firstLoad.first(where: { $0.template.name == "context7" })?.headerPrompts, ["CONTEXT7_API_KEY"])

        try await fixture.claudeStore.writeMCPServers([
            "context7": AgentCLIKit.ClaudeMCPServerConfig(
                command: nil,
                args: nil,
                url: "https://mcp.context7.com/mcp",
                headers: nil,
                env: nil
            )
        ])

        let secondLoad = try await fixture.service.loadRecommended()
        XCTAssertNil(secondLoad.first(where: { $0.template.name == "context7" }))
        XCTAssertNotNil(secondLoad.first(where: { $0.template.name == "playwright" }))
    }

    func testAvailableAgentsUsesDetectionStateAndTransportSupport() async {
        let fixture = try? MCPServiceFixture(
            statuses: [
                "claude": .connected(path: "/usr/local/bin/claude", version: "1.0.0"),
                "codex": .error("Needs auth")
            ]
        )
        guard let fixture else {
            XCTFail("Failed to create fixture")
            return
        }
        defer { fixture.cleanup() }

        let available = await fixture.service.availableAgents()
        let checkAllCount = await fixture.providerDetection.checkAllCount()

        XCTAssertEqual(checkAllCount, 1)
        XCTAssertEqual(available.count, 2)
        XCTAssertEqual(available.first(where: { $0.agentId == "claude" })?.supportedTransports, [.stdio, .http])
        XCTAssertEqual(available.first(where: { $0.agentId == "codex" })?.supportedTransports, [.stdio])
    }
}

@MainActor
private struct MCPServiceFixture {
    let rootDirectory: URL
    let homeDirectory: URL
    let codexConfigURL: URL
    let codexIntegration: MCPIntegrationDefinition
    let claudeStore: AgentCLIKit.ClaudeConfigStore
    let codexStore: AgentCLIKit.CodexConfigStore
    let providerDetection: MCPTestProviderDetectionService
    let service: DefaultMCPService

    init(statuses: [String: ProviderStatus] = [
        "claude": .connected(path: "/usr/local/bin/claude", version: "1.0.0"),
        "codex": .connected(path: "/usr/local/bin/codex", version: "1.0.0")
    ]) throws {
        rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        homeDirectory = rootDirectory.appendingPathComponent("home", isDirectory: true)
        codexConfigURL = rootDirectory.appendingPathComponent("codex/config.toml")
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true, attributes: nil)
        claudeStore = AgentCLIKit.ClaudeConfigStore(homeDirectoryURL: homeDirectory)
        codexStore = AgentCLIKit.CodexConfigStore(fileURL: codexConfigURL)
        providerDetection = MCPTestProviderDetectionService(statuses: statuses)
        codexIntegration = MCPIntegrationDefinition(
            configPath: codexConfigURL.path,
            serversKeyPath: ["mcp_servers"],
            format: .toml,
            adapterId: "passthrough",
            supportsHttp: false
        )

        let registry = ServiceTestAgentRegistry(
            agents: [
                AgentDefinition(
                    id: "claude",
                    name: "Claude Code",
                    installCommand: nil,
                    docUrl: nil,
                    provider: nil,
                    skillsDirectory: nil,
                    mcp: MCPIntegrationDefinition(
                        configPath: "~/.claude.json",
                        serversKeyPath: ["mcpServers"],
                        format: .json,
                        adapterId: "passthrough",
                        supportsHttp: true
                    )
                ),
                AgentDefinition(
                    id: "codex",
                    name: "Codex",
                    installCommand: nil,
                    docUrl: nil,
                    provider: nil,
                    skillsDirectory: nil,
                    mcp: codexIntegration
                )
            ]
        )

        service = DefaultMCPService(
            claudeConfigStore: claudeStore,
            codexConfigStore: codexStore,
            providerDetection: providerDetection,
            agentRegistry: registry,
            bundle: Bundle(for: MCPServiceTests.self)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func writeCodexServers(_ servers: ServerMap) async throws {
        let codexServers = servers.mapValues { server in
            AgentCLIKit.CodexMCPServerConfig(
                command: server["command"] as? String,
                args: server["args"] as? [String],
                env: server["env"] as? [String: String],
                url: server["url"] as? String,
                httpHeaders: server["headers"] as? [String: String],
                enabled: (server["disabled"] as? Bool).map { !$0 }
            )
        }
        try await codexStore.writeMCPServers(codexServers)
    }

    func writeTrustedProjects() throws {
        let configURL = homeDirectory.appendingPathComponent(".claude.json")
        let root: [String: Any] = [
            "projects": [
                "/tmp/project": [
                    "hasTrustDialogAccepted": true,
                    "hasCompletedProjectOnboarding": true
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    func readClaudeRoot() throws -> [String: Any] {
        let configURL = homeDirectory.appendingPathComponent(".claude.json")
        let data = try Data(contentsOf: configURL)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
