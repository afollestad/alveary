struct AgentConfig: Sendable, Equatable {
    let providerId: String
    let sessionId: String
    let workingDirectory: String
    let permissionMode: String?
    let model: String?
    let effort: String?
    let initialPrompt: String?
}

struct AgentSpawnConfig: Sendable, Equatable {
    let providerId: String
    let workingDirectory: String
    let permissionMode: String?
    let model: String?
    let effort: String?
    let initialPrompt: String?
}
