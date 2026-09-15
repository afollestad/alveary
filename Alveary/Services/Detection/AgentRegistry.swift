protocol AgentRegistry: Sendable {
    var agents: [AgentDefinition] { get }
    func agent(for id: String) -> AgentDefinition?
}

protocol HarnessRegistry: Sendable {
    var harnesses: [HarnessDefinition] { get }
    func harness(for id: String) -> HarnessDefinition?
}
