import Foundation

/// How an agent's global instructions path relates to the shared `~/.agents/AGENTS.md` file.
enum AgentInstructionsLinkState: Equatable, Sendable {
    /// The agent's path is a symlink that resolves to the shared file.
    case linked
    /// The agent's path is a symlink that resolves somewhere else; left alone.
    case linkedElsewhere(target: String)
    /// The agent's path is a real, non-empty file.
    case hasOwnFile(path: String)
    /// The agent's path is missing or empty.
    case absent(path: String)
}

/// Reads and writes the shared global agent instructions file, and manages
/// opt-in migration of per-agent instructions files into symlinks to it.
protocol GlobalAgentInstructionsService: Sendable {
    /// Display string for the shared instructions file, such as `~/.agents/AGENTS.md`.
    var sharedPathDescription: String { get }

    /// Returns the shared file's content, or an empty string when it does not exist.
    func loadShared() async throws -> String

    /// Writes the shared file atomically, creating its parent directory when needed.
    func saveShared(_ markdown: String) async throws

    /// Returns the link state for every agent that declares an instructions path, keyed by agent id.
    func linkStates() async -> [String: AgentInstructionsLinkState]

    /// Appends the agent file's content to the shared file under a migration marker.
    /// The agent's own file is left untouched.
    func copyIntoShared(agentID: String) async throws

    /// Replaces the agent's instructions file with a symlink to the shared file.
    /// The original file is first backed up beside itself as `<filename>.backup`,
    /// and its content is optionally appended to the shared file.
    func link(agentID: String, copyingContents: Bool) async throws
}

enum GlobalAgentInstructionsError: LocalizedError, Equatable {
    case unknownAgent(String)
    case unsupportedAgent(String)

    var errorDescription: String? {
        switch self {
        case .unknownAgent(let id):
            return "Unknown agent \"\(id)\"."
        case .unsupportedAgent(let id):
            return "Agent \"\(id)\" has no global instructions file."
        }
    }
}
