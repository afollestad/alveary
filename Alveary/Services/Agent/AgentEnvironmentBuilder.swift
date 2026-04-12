protocol AgentEnvironmentBuilder: Sendable {
    func buildEnvironment(providerEnv: [String: String]?) -> [String: String]
}
