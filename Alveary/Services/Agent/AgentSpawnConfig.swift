/// Provider-neutral app request for starting or reconfiguring an agent runtime.
///
/// `AgentCLIKitHostAdapter` converts this Alveary model into `AgentCLIKit.AgentSpawnConfig`.
/// It intentionally contains only host settings; provider session IDs and launch arguments
/// are owned by `AgentCLIKit`.
struct AgentSpawnConfig: Sendable, Equatable {
    let providerId: String
    let workingDirectory: String
    let permissionMode: String?
    let planModeEnabled: Bool?
    let model: String?
    let effort: String?
    let speedMode: AgentSpeedMode?
    let sessionFork: AgentSessionForkRequest?
    let initialPrompt: String?
    let initialGoal: String?

    init(
        providerId: String,
        workingDirectory: String,
        permissionMode: String? = nil,
        planModeEnabled: Bool? = nil,
        model: String? = nil,
        effort: String? = nil,
        speedMode: AgentSpeedMode? = nil,
        sessionFork: AgentSessionForkRequest? = nil,
        initialPrompt: String? = nil,
        initialGoal: String? = nil
    ) {
        self.providerId = providerId
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.planModeEnabled = planModeEnabled
        self.model = model
        self.effort = effort
        self.speedMode = speedMode
        self.sessionFork = sessionFork
        self.initialPrompt = initialPrompt
        self.initialGoal = initialGoal
    }
}

enum AgentSessionForkMode: String, Sendable, Equatable {
    case local
    case worktree
}

struct AgentSessionForkRequest: Sendable, Equatable {
    let sourceSessionId: String
    let sourceWorkingDirectory: String?
    let mode: AgentSessionForkMode

    init(
        sourceSessionId: String,
        sourceWorkingDirectory: String?,
        mode: AgentSessionForkMode
    ) {
        self.sourceSessionId = sourceSessionId
        self.sourceWorkingDirectory = sourceWorkingDirectory.map(CanonicalPath.normalize)
        self.mode = mode
    }
}
