import Foundation

enum AgentError: LocalizedError, Sendable, Equatable {
    case cliNotInstalled(String)
    case spawnFailed(String)
    case stdinClosed

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled(let provider):
            return "\(provider) CLI is not installed"
        case .spawnFailed(let message):
            return message
        case .stdinClosed:
            return "Agent input is closed"
        }
    }
}
