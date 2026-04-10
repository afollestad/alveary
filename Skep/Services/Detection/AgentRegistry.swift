protocol AgentRegistry: Sendable {
    var agents: [AgentDefinition] { get }
    func agent(for id: String) -> AgentDefinition?
}

protocol ProviderRegistry: Sendable {
    var providers: [ProviderDefinition] { get }
    func provider(for id: String) -> ProviderDefinition?
}
