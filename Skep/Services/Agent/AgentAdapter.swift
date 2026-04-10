import Foundation

enum SessionContinuity: Sendable, Equatable {
    case preserved
    case restartedFresh
}

struct SessionLaunchDecision: Sendable, Equatable {
    let args: [String]
    let continuity: SessionContinuity
}

protocol AgentAdapter: Sendable {
    func buildArgs(config: AgentConfig) -> [String]
    func envOverrides(config: AgentConfig) -> [String: String]
    func decode(_ json: [String: Any]) -> [ConversationEvent]
    func finalize() -> [ConversationEvent]
    func sendMessage(_ message: String, to process: Process) throws
    func sessionFilePath(sessionId: String, cwd: String) -> String?
    func canResumeSession(sessionId: String, cwd: String) -> Bool
    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision

    var supportsBidirectionalStreaming: Bool { get }
    var supportsMidTurnSteering: Bool { get }
}
