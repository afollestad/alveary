import XCTest

@testable import Skep

final class ProviderRegistryTests: XCTestCase {
    func testClaudeMetadataIsAvailableThroughSharedAndProviderRegistries() {
        let agentRegistry = DefaultAgentRegistry()
        let providerRegistry = DefaultProviderRegistry(agentRegistry: agentRegistry)

        let agent = agentRegistry.agent(for: "claude")
        let provider = providerRegistry.provider(for: "claude")

        XCTAssertEqual(agent?.name, "Claude Code")
        XCTAssertEqual(agent?.installCommand, "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(agent?.mcp?.configPath, "~/.claude.json")
        XCTAssertEqual(provider?.cli, "claude")
        XCTAssertEqual(provider?.permissionModeFlag, "--permission-mode")
        XCTAssertEqual(provider?.supportedEffortLevels, ["low", "medium", "high", "max"])
        XCTAssertTrue(provider?.supportsBidirectionalStreaming == true)
        XCTAssertTrue(provider?.supportsMidTurnSteering == true)
        XCTAssertNil(agentRegistry.agent(for: "missing"))
        XCTAssertNil(providerRegistry.provider(for: "missing"))
    }
}
