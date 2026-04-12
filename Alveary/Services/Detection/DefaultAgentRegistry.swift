final class DefaultAgentRegistry: AgentRegistry, Sendable {
    let agents: [AgentDefinition] = [
        AgentDefinition(
            id: "claude",
            name: "Claude Code",
            installCommand: "curl -fsSL https://claude.ai/install.sh | bash",
            docUrl: "https://code.claude.com/docs/en/quickstart",
            provider: ProviderDefinition(
                id: "claude",
                name: "Claude Code",
                cli: "claude",
                commands: ["claude"],
                versionArgs: ["--version"],
                autoApproveFlag: "--dangerously-skip-permissions",
                initialPromptFlag: nil,
                resumeFlag: "--resume",
                sessionIdFlag: "--session-id",
                planActivateCommand: "/plan",
                structuredOutputArgs: ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"],
                structuredInputArgs: ["--input-format", "stream-json"],
                execSubcommand: nil,
                supportsBidirectionalStreaming: true,
                supportsMidTurnSteering: true,
                permissionModeFlag: "--permission-mode",
                supportedPermissionModes: [
                    PermissionModeOption(
                        value: "default",
                        label: "Default",
                        description: "Safe default; denied writes return as tool errors in non-interactive mode."
                    ),
                    PermissionModeOption(
                        value: "plan",
                        label: "Plan",
                        description: "Read-only exploration and planning."
                    ),
                    PermissionModeOption(
                        value: "acceptEdits",
                        label: "Auto-Edit",
                        description: "Auto-accept file edits while keeping stronger checks for other actions."
                    ),
                    PermissionModeOption(
                        value: "auto",
                        label: "Auto",
                        description: "Auto-approve most actions with safety checks."
                    ),
                    PermissionModeOption(
                        value: "bypassPermissions",
                        label: "Auto-Approve",
                        description: "Bypass permission checks entirely."
                    )
                ],
                suggestedWriteEscalationMode: "acceptEdits",
                writeEscalationEligibleTools: ["Write", "Edit", "MultiEdit"],
                effortFlag: "--effort",
                supportedEffortLevels: ["low", "medium", "high", "max"]
            ),
            skillsDirectory: "~/.claude/skills",
            mcp: MCPIntegrationDefinition(
                configPath: "~/.claude.json",
                serversKeyPath: ["mcpServers"],
                format: .json,
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
