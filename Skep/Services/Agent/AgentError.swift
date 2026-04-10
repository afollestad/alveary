enum AgentError: Error, Sendable, Equatable {
    case cliNotInstalled(String)
    case spawnFailed(String)
    case stdinClosed
}
