struct PermissionModeOption: Sendable, Equatable {
    let value: String
    let label: String
    let description: String
}

struct ProviderDefinition: Sendable, Equatable {
    let id: String
    let commands: [String]
    let versionArgs: [String]
    let supportsMidTurnSteering: Bool
    let supportedPermissionModes: [PermissionModeOption]?
}
