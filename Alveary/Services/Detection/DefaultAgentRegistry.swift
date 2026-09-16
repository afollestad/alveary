import AgentCLIKit
import Foundation

final class DefaultAgentRegistry: AgentRegistry, Sendable {
    let agents: [AgentDefinition]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let openCodeConfigURL = OpenCodeConfigStore.configFileURL(environment: environment, homeDirectory: homeDirectory)
        let openCodeDirectory = Self.displayPath(openCodeConfigURL.deletingLastPathComponent(), homeDirectory: homeDirectory)
        let openCodeConfigPath = Self.displayPath(openCodeConfigURL, homeDirectory: homeDirectory)
        agents = Self.baseAgents + [Self.openCodeAgent(configDirectory: openCodeDirectory, configPath: openCodeConfigPath)]
    }

    private static let baseAgents: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            name: "Claude Code",
            installCommand: "curl -fsSL https://claude.ai/install.sh | bash",
            signInCommand: "claude auth login",
            docUrl: "https://code.claude.com/docs/en/quickstart",
            harness: HarnessDefinition(
                id: "claude",
                commands: ["claude"],
                versionArgs: ["--version"],
                supportsMidTurnSteering: true,
                supportedPermissionModes: [
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
            ),
            skillsDirectory: "~/.claude/skills",
            instructionsPath: "~/.claude/CLAUDE.md",
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
            installCommand: "curl -fsSL https://chatgpt.com/codex/install.sh | sh",
            signInCommand: "codex login",
            docUrl: "https://developers.openai.com/codex/app-server",
            harness: HarnessDefinition(
                id: "codex",
                commands: ["codex"],
                versionArgs: ["--version"],
                supportsMidTurnSteering: true,
                supportedPermissionModes: [
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
            ),
            skillsDirectory: "~/.codex/skills",
            instructionsPath: "~/.codex/AGENTS.md",
            mcp: MCPIntegrationDefinition(
                configPath: "~/.codex/config.toml",
                serversKeyPath: ["mcp_servers"],
                format: .toml,
                adapterId: "passthrough",
                supportsHttp: true
            )
        )
    ]

    private static func openCodeAgent(configDirectory: String, configPath: String) -> AgentDefinition {
        AgentDefinition(
            id: "opencode",
            name: "OpenCode",
            installCommand: "curl -fsSL https://opencode.ai/install | bash",
            signInCommand: "opencode auth login",
            docUrl: "https://opencode.ai/docs/",
            harness: HarnessDefinition(
                id: "opencode",
                commands: ["opencode"],
                versionArgs: ["--version"],
                supportsMidTurnSteering: true,
                supportedPermissionModes: [
                    PermissionModeOption(
                        value: "configured", label: "Configured", description: "Use the permissions configured in OpenCode."
                    ),
                    PermissionModeOption(
                        value: "ask", label: "Ask", description: "Ask before tool actions that require permission."
                    ),
                    PermissionModeOption(
                        value: "fullAccess", label: "Full access", description: "Allow tool actions without asking for approval."
                    )
                ]
            ),
            skillsDirectory: "\(configDirectory)/skills",
            instructionsPath: "\(configDirectory)/AGENTS.md",
            mcp: MCPIntegrationDefinition(
                configPath: configPath,
                serversKeyPath: ["mcp"],
                format: .json,
                adapterId: "opencode",
                supportsHttp: true
            )
        )
    }

    func agent(for id: String) -> AgentDefinition? {
        agents.first { $0.id == id }
    }

    /// Keep familiar home-relative display paths while respecting an explicit native XDG location.
    private static func displayPath(_ url: URL, homeDirectory: URL) -> String {
        let prefix = homeDirectory.path + "/"
        return url.path.hasPrefix(prefix) ? "~/" + url.path.dropFirst(prefix.count) : url.path
    }
}

final class DefaultHarnessRegistry: HarnessRegistry, Sendable {
    private let agentRegistry: AgentRegistry

    init(agentRegistry: AgentRegistry) {
        self.agentRegistry = agentRegistry
    }

    var harnesses: [HarnessDefinition] {
        agentRegistry.agents.compactMap(\.harness)
    }

    func harness(for id: String) -> HarnessDefinition? {
        agentRegistry.agent(for: id)?.harness
    }
}
