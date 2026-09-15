import XCTest

@testable import Alveary

final class HarnessRegistryTests: XCTestCase {
    func testClaudeMetadataIsAvailableThroughSharedAndHarnessRegistries() {
        let agentRegistry = DefaultAgentRegistry()
        let harnessRegistry = DefaultHarnessRegistry(agentRegistry: agentRegistry)

        let agent = agentRegistry.agent(for: "claude")
        let harness = harnessRegistry.harness(for: "claude")

        XCTAssertEqual(agent?.name, "Claude Code")
        XCTAssertEqual(agent?.installCommand, "curl -fsSL https://claude.ai/install.sh | bash")
        XCTAssertEqual(agent?.mcp?.configPath, "~/.claude.json")
        XCTAssertEqual(harness?.commands, ["claude"])
        XCTAssertEqual(harness?.versionArgs, ["--version"])
        XCTAssertEqual(
            harness?.supportedPermissionModes,
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
        XCTAssertTrue(harness?.supportsMidTurnSteering == true)
        XCTAssertNil(agentRegistry.agent(for: "missing"))
        XCTAssertNil(harnessRegistry.harness(for: "missing"))
    }

    func testCodexPermissionMetadataUsesDisplayLabelsWithoutChangingValues() {
        let harness = DefaultAgentRegistry().agent(for: "codex")?.harness

        XCTAssertEqual(
            harness?.supportedPermissionModes,
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
