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
        XCTAssertEqual(provider?.commands, ["claude"])
        XCTAssertEqual(provider?.versionArgs, ["--version"])
        XCTAssertEqual(
            provider?.supportedPermissionModes,
            [
                PermissionModeOption(
                    value: "default",
                    label: "Default",
                    description: "Ask before file edits and restricted tool actions."
                ),
                PermissionModeOption(
                    value: "acceptEdits",
                    label: "Accept edits",
                    description: "Automatically allow file edits, but ask for other sensitive actions."
                ),
                PermissionModeOption(
                    value: "auto",
                    label: "Automatic",
                    description: "Automatically approve most actions with safety checks."
                ),
                PermissionModeOption(
                    value: "bypassPermissions",
                    label: "Bypass permissions",
                    description: "Bypass all permission checks. Use only in sandboxed environments."
                )
            ]
        )
        XCTAssertTrue(provider?.supportsMidTurnSteering == true)
        XCTAssertNil(agentRegistry.agent(for: "missing"))
        XCTAssertNil(providerRegistry.provider(for: "missing"))
    }

    func testCodexPermissionMetadataUsesDisplayLabelsWithoutChangingValues() {
        let provider = DefaultAgentRegistry().agent(for: "codex")?.provider

        XCTAssertEqual(
            provider?.supportedPermissionModes,
            [
                PermissionModeOption(
                    value: "untrusted",
                    label: "Ask for approval",
                    description: "Always ask to edit external files and use the internet."
                ),
                PermissionModeOption(
                    value: "on-request",
                    label: "Approve for me",
                    description: "Only ask for actions detected as potentially unsafe."
                ),
                PermissionModeOption(
                    value: "never",
                    label: "Full access",
                    description: "Unrestricted access to the internet and any file on your computer."
                )
            ]
        )
    }
}
