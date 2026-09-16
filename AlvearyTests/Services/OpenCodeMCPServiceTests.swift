import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
final class OpenCodeMCPServiceTests: XCTestCase {
    func testMCPSettingsConvertTransportsAndPreserveNativeFieldsAndPolicy() async throws {
        let fixture = try OpenCodeMCPFixture()
        defer { fixture.cleanup() }
        let source = """
        {
          // Native policy order is meaningful.
          "permission": {"bash": {"*": "deny", "git *": "allow"}},
          "mcp": {"docs": {"type": "remote", "url": "https://example.invalid/old", "enabled": false,
            "oauth": false, "timeout": 4200, "extension": {"keep": true}},
            "other": {"enabled": false}}
        }
        """
        try source.write(to: fixture.configURL, atomically: true, encoding: .utf8)

        try await fixture.service.addServer(MCPServer(
            name: "docs", transport: .stdio, command: "npx", args: ["-y", "fixture-server"], url: nil,
            headers: nil, env: ["REGION": "test"], harnesses: []
        ), for: ["opencode"])

        let native = try await fixture.store.readMCPServers()
        XCTAssertEqual(native["docs"]?.type, "local")
        XCTAssertEqual(native["docs"]?.command, ["npx", "-y", "fixture-server"])
        XCTAssertEqual(native["docs"]?.environment, ["REGION": "test"])
        XCTAssertNil(native["docs"]?.url)
        XCTAssertEqual(native["docs"]?.enabled, false)
        XCTAssertEqual(native["docs"]?.oauth, .bool(false))
        XCTAssertEqual(native["docs"]?.timeout, 4200)
        XCTAssertEqual(native["docs"]?.additionalFields["extension"], .object(["keep": .bool(true)]))
        XCTAssertEqual(native["other"], OpenCodeMCPServerConfig(enabled: false))
        let updated = try String(contentsOf: fixture.configURL, encoding: .utf8)
        let mcpPrefixEnd = try XCTUnwrap(source.range(of: "\"mcp\": ")).upperBound
        XCTAssertTrue(updated.hasPrefix(String(source[..<mcpPrefixEnd])))
        let visible = try await fixture.service.loadAll()
        let server = try XCTUnwrap(visible.first { $0.name == "docs" })
        XCTAssertEqual(server.command, "npx")
        XCTAssertEqual(server.args, ["-y", "fixture-server"])
        XCTAssertEqual(server.env, ["REGION": "test"])
        XCTAssertEqual(server.harnesses, ["opencode"])
    }

    func testRemoteEditDropsLocalTransportFieldsAndRemoveKeepsOtherServers() async throws {
        let fixture = try OpenCodeMCPFixture()
        defer { fixture.cleanup() }
        try await fixture.store.writeMCPServers([
            "docs": OpenCodeMCPServerConfig(type: "local", command: ["old"], environment: ["KEEP": "no"], oauth: .bool(false)),
            "other": OpenCodeMCPServerConfig(enabled: false)
        ])
        let server = MCPServer(
            name: "docs", transport: .http, command: nil, args: nil, url: "https://example.invalid/new",
            headers: ["Authorization": "Bearer fixture"], env: nil, harnesses: []
        )
        try await fixture.service.addServer(server, for: ["opencode"])
        let remote = try await fixture.store.readMCPServers()["docs"]
        XCTAssertEqual(remote?.type, "remote")
        XCTAssertNil(remote?.command)
        XCTAssertNil(remote?.environment)
        XCTAssertEqual(remote?.headers, ["Authorization": "Bearer fixture"])
        XCTAssertEqual(remote?.oauth, .bool(false))
        try await fixture.service.removeServer(server)
        let remaining = try await fixture.store.readMCPServers()
        XCTAssertEqual(Set(remaining.keys), ["other"])
    }

    func testMalformedNativeConfigFailsClosedBeforeWritingOtherHarnesses() async throws {
        let fixture = try OpenCodeMCPFixture()
        defer { fixture.cleanup() }
        let invalid = "{\"permission\": broken"
        try invalid.write(to: fixture.configURL, atomically: true, encoding: .utf8)
        let original = ClaudeMCPServerConfig(command: "existing", args: nil, url: nil, headers: nil, env: nil)
        try await fixture.claudeStore.writeMCPServers(["docs": original])
        let server = MCPServer(
            name: "docs", transport: .stdio, command: "fixture", args: nil, url: nil,
            headers: nil, env: nil, harnesses: []
        )
        do {
            try await fixture.service.addServer(server, for: ["claude", "opencode"])
            XCTFail("Unparseable config must not be replaced")
        } catch {}
        do {
            try await fixture.service.removeServer(server)
            XCTFail("Unparseable config must stop removals before any writes")
        } catch {}
        XCTAssertEqual(try String(contentsOf: fixture.configURL, encoding: .utf8), invalid)
        let other = try await fixture.claudeStore.readMCPServers()
        XCTAssertEqual(other["docs"], original)
    }
}

@MainActor
private struct OpenCodeMCPFixture {
    let root: URL
    let configURL: URL
    let store: OpenCodeConfigStore
    let claudeStore: ClaudeConfigStore
    let service: DefaultMCPService

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configURL = root.appendingPathComponent("opencode.jsonc")
        store = OpenCodeConfigStore(fileURL: configURL)
        claudeStore = ClaudeConfigStore(fileURL: root.appendingPathComponent("claude.json"))
        service = DefaultMCPService(
            claudeConfigStore: claudeStore, codexConfigStore: CodexConfigStore(fileURL: root.appendingPathComponent("codex.toml")),
            openCodeConfigStore: store, harnessDetection: MCPTestHarnessDetectionService(statuses: [:]), agentRegistry: DefaultAgentRegistry()
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
