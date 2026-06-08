final class DefaultAgentRegistry: AgentRegistry, Sendable {
    let agents: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            name: "Claude Code",
            installCommand: "curl -fsSL https://claude.ai/install.sh | bash",
            docUrl: "https://code.claude.com/docs/en/quickstart",
            provider: ProviderDefinition(
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
                    )
                ]
            ),
            skillsDirectory: "~/.claude/skills",
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
            docUrl: "https://developers.openai.com/codex/app-server",
            provider: ProviderDefinition(
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
            mcp: MCPIntegrationDefinition(
                configPath: "~/.codex/config.toml",
                serversKeyPath: ["mcp_servers"],
                format: .toml,
                adapterId: "passthrough",
                supportsHttp: true
            )
        )
    ]

    func agent(for id: String) -> AgentDefinition? {
        agents.first { $0.id == id }
    }
}

final class DefaultProviderRegistry: ProviderRegistry, Sendable {
    private let agentRegistry: AgentRegistry

    init(agentRegistry: AgentRegistry) {
        self.agentRegistry = agentRegistry
    }

    var providers: [ProviderDefinition] {
        agentRegistry.agents.compactMap(\.provider)
    }

    func provider(for id: String) -> ProviderDefinition? {
        agentRegistry.agent(for: id)?.provider
    }
}
