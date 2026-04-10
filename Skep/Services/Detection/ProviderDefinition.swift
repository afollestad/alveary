struct PermissionModeOption: Sendable, Equatable {
    let value: String
    let label: String
    let description: String
}

struct ProviderDefinition: Sendable, Equatable {
    let id: String
    let name: String
    let cli: String
    let commands: [String]
    let versionArgs: [String]
    let autoApproveFlag: String?
    let initialPromptFlag: String?
    let resumeFlag: String?
    let sessionIdFlag: String?
    let planActivateCommand: String?
    let structuredOutputArgs: [String]?
    let structuredInputArgs: [String]?
    let execSubcommand: String?
    let supportsBidirectionalStreaming: Bool
    let supportsMidTurnSteering: Bool
    let permissionModeFlag: String?
    let supportedPermissionModes: [PermissionModeOption]?
    let suggestedWriteEscalationMode: String?
    let writeEscalationEligibleTools: Set<String>
    let effortFlag: String?
    let supportedEffortLevels: [String]?
}
