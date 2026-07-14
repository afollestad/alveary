import AgentCLIKit

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
    let initialPromptMetadata: [String: AgentCLIKit.JSONValue]
    let additionalWorkspaceRoots: [String]
    let allowedDirectories: [String]
    let hostToolServer: AgentCLIKit.AgentHostToolServerMetadata
    let hostTools: [AgentCLIKit.AgentHostToolDefinition]
    let initialGoal: String?
    let isAutomatedScheduledTurn: Bool

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
        initialPromptMetadata: [String: AgentCLIKit.JSONValue] = [:],
        additionalWorkspaceRoots: [String] = [],
        allowedDirectories: [String] = [],
        hostToolServer: AgentCLIKit.AgentHostToolServerMetadata = AgentCLIKit.AgentHostToolServerMetadata(),
        hostTools: [AgentCLIKit.AgentHostToolDefinition] = [],
        initialGoal: String? = nil,
        isAutomatedScheduledTurn: Bool = false
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
        self.initialPromptMetadata = initialPromptMetadata
        self.additionalWorkspaceRoots = additionalWorkspaceRoots.map(CanonicalPath.normalize)
        self.allowedDirectories = allowedDirectories.map(CanonicalPath.normalize)
        self.hostToolServer = hostToolServer
        self.hostTools = hostTools
        self.initialGoal = initialGoal
        self.isAutomatedScheduledTurn = isAutomatedScheduledTurn
    }

    func withoutHostTools() -> AgentSpawnConfig {
        AgentSpawnConfig(
            copying: self,
            hostToolServer: AgentCLIKit.AgentHostToolServerMetadata(),
            hostTools: []
        )
    }

    private init(
        copying config: AgentSpawnConfig,
        hostToolServer: AgentCLIKit.AgentHostToolServerMetadata,
        hostTools: [AgentCLIKit.AgentHostToolDefinition]
    ) {
        providerId = config.providerId
        workingDirectory = config.workingDirectory
        permissionMode = config.permissionMode
        planModeEnabled = config.planModeEnabled
        model = config.model
        effort = config.effort
        reasoningSummaryMode = config.reasoningSummaryMode
        speedMode = config.speedMode
        sessionFork = config.sessionFork
        initialPrompt = config.initialPrompt
        initialPromptAttachments = config.initialPromptAttachments
        initialPromptMetadata = config.initialPromptMetadata
        // Preserve the authorization snapshot verbatim. Re-normalizing here could follow a
        // same-path symlink replacement between the primary launch and its fallback attempt.
        additionalWorkspaceRoots = config.additionalWorkspaceRoots
        allowedDirectories = config.allowedDirectories
        self.hostToolServer = hostToolServer
        self.hostTools = hostTools
        initialGoal = config.initialGoal
        isAutomatedScheduledTurn = config.isAutomatedScheduledTurn
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
