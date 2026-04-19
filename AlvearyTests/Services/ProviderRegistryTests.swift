import XCTest

@testable import Alveary

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
        XCTAssertEqual(
            provider?.supportedPermissionModes,
            [
                PermissionModeOption(
                    value: "default",
                    label: "Default permissions",
                    description: "Safe default; denied writes return as tool errors in non-interactive mode."
                ),
                PermissionModeOption(
                    value: "plan",
                    label: "Plan",
                    description: "Read-only exploration and planning."
                ),
                PermissionModeOption(
                    value: "acceptEdits",
                    label: "Accept edits",
                    description: "Auto-accept file edits while keeping stronger checks for other actions."
                ),
                PermissionModeOption(
                    value: "auto",
                    label: "Automatic",
                    description: "Auto-approve most actions with safety checks."
                )
            ]
        )
        XCTAssertEqual(provider?.supportedEffortLevels, AppSettings.supportedEffortLevels)
        XCTAssertTrue(provider?.supportsBidirectionalStreaming == true)
        XCTAssertTrue(provider?.supportsMidTurnSteering == true)
        XCTAssertNil(agentRegistry.agent(for: "missing"))
        XCTAssertNil(providerRegistry.provider(for: "missing"))
    }
}
