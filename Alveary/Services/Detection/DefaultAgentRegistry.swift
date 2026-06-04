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
                        label: "Untrusted",
                        description: "Only known-safe read-only commands run without approval; other commands prompt."
                    ),
                    PermissionModeOption(
                        value: "on-request",
                        label: "On request",
                        description: "Codex decides when to request approval for higher-risk commands."
                    ),
                    PermissionModeOption(
                        value: "never",
                        label: "Never ask",
                        description: "Codex never prompts for command approval and returns failures directly to the model."
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
