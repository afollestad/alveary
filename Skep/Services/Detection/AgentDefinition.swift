struct MCPIntegrationDefinition: Sendable, Equatable {
    let configPath: String
    let serversKeyPath: [String]
    let format: ConfigFormat
    let adapterId: String
    let supportsHttp: Bool

    enum ConfigFormat: Sendable, Equatable {
        case json
        case toml
    }
}

struct AgentDefinition: Sendable, Equatable {
    let id: String
    let name: String
    let installCommand: String?
    let docUrl: String?
    let provider: ProviderDefinition?
    let skillsDirectory: String?
    let mcp: MCPIntegrationDefinition?
}
