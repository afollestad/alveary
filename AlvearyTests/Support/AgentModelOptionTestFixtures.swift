import AgentCLIKit

enum AgentModelOptionTestFixtures {
    static let medium = AgentCLIKit.AgentProviderOption(
        value: "medium",
        label: "Medium",
        description: "Use medium reasoning effort."
    )

    static let high = AgentCLIKit.AgentProviderOption(
        value: "high",
        label: "High",
        description: "Use high reasoning effort."
    )

    static let xhigh = AgentCLIKit.AgentProviderOption(
        value: "xhigh",
        label: "Extra High",
        description: "Use extra high reasoning effort."
    )

    static let max = AgentCLIKit.AgentProviderOption(
        value: "max",
        label: "Max",
        description: "Use max reasoning effort."
    )

    static let claudeDefaultEfforts = [low, medium, high, max]
    static let claudeOpusEfforts = [low, medium, high, xhigh, max]
    static let codexDefaultEfforts = [low, medium, high, xhigh]

    static let claudeModelOptions: [AgentCLIKit.AgentModelOption] = [
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "default",
            model: nil,
            label: "Provider default",
            isDefault: true,
            supportedEffortOptions: claudeDefaultEfforts,
            defaultEffortOption: medium
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "sonnet",
            model: "sonnet",
            label: "Sonnet",
            supportedEffortOptions: claudeDefaultEfforts,
            defaultEffortOption: medium
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "opus",
            model: "opus",
            label: "Opus",
            supportedEffortOptions: claudeOpusEfforts,
            defaultEffortOption: xhigh
        )
    ]

    static let codexModelOptions: [AgentCLIKit.AgentModelOption] = [
        AgentCLIKit.AgentModelOption(
            providerId: .codex,
            id: "gpt-5.5",
            model: "gpt-5.5",
            label: "GPT-5.5",
            isDefault: true,
            supportedEffortOptions: codexDefaultEfforts,
            defaultEffortOption: medium
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .codex,
            id: "gpt-5.4-mini",
            model: "gpt-5.4-mini",
            label: "GPT-5.4-Mini",
            supportedEffortOptions: [low, medium],
            defaultEffortOption: low
        )
    ]

    private static let low = AgentCLIKit.AgentProviderOption(
        value: "low",
        label: "Low",
        description: "Use low reasoning effort."
    )
}
