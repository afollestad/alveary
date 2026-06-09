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

    static let claudeSonnetEfforts = [low, medium, high, max]
    static let claudeFableEfforts = [low, medium, high, xhigh, max]
    static let claudeOpusEfforts = [low, medium, high, xhigh, max]
    static let claudeHaikuEfforts = [low, medium, high]
    static let codexDefaultEfforts = [low, medium, high, xhigh]

    static let claudeModelOptions: [AgentCLIKit.AgentModelOption] = [
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "sonnet",
            model: "sonnet",
            label: "Sonnet",
            isDefault: true,
            supportedEffortOptions: claudeSonnetEfforts,
            defaultEffortOption: high
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "fable",
            model: "fable",
            label: "Fable",
            supportedEffortOptions: claudeFableEfforts,
            defaultEffortOption: high
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "opus",
            model: "opus",
            label: "Opus",
            supportedEffortOptions: claudeOpusEfforts,
            defaultEffortOption: high
        ),
        AgentCLIKit.AgentModelOption(
            providerId: .claude,
            id: "haiku",
            model: "haiku",
            label: "Haiku",
            supportedEffortOptions: claudeHaikuEfforts,
            defaultEffortOption: medium
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
