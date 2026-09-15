protocol AgentEnvironmentBuilder: Sendable {
    func buildEnvironment(harnessEnv: [String: String]?) -> [String: String]
}
