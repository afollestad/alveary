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
    let reasoningSummaryMode: AgentReasoningSummaryMode?
    let speedMode: AgentSpeedMode?
    let sessionFork: AgentSessionForkRequest?
    let initialPrompt: String?
    let initialPromptAttachments: [LocalImageAttachment]
    let initialGoal: String?

    init(
        providerId: String,
        workingDirectory: String,
        permissionMode: String? = nil,
        planModeEnabled: Bool? = nil,
        model: String? = nil,
        effort: String? = nil,
        reasoningSummaryMode: AgentReasoningSummaryMode? = nil,
        speedMode: AgentSpeedMode? = nil,
        sessionFork: AgentSessionForkRequest? = nil,
        initialPrompt: String? = nil,
        initialPromptAttachments: [LocalImageAttachment] = [],
        initialGoal: String? = nil
    ) {
        self.providerId = providerId
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.planModeEnabled = planModeEnabled
        self.model = model
        self.effort = effort
        self.reasoningSummaryMode = reasoningSummaryMode
        self.speedMode = speedMode
        self.sessionFork = sessionFork
        self.initialPrompt = initialPrompt
        self.initialPromptAttachments = initialPromptAttachments
        self.initialGoal = initialGoal
    }
}

enum AgentReasoningSummaryMode: String, Sendable, Equatable {
    case auto
    case concise
    case detailed
    case none
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
