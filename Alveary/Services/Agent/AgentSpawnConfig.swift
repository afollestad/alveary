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
    let initialPrompt: String?

    init(
        providerId: String,
        workingDirectory: String,
        permissionMode: String? = nil,
        planModeEnabled: Bool? = nil,
        model: String? = nil,
        effort: String? = nil,
        speedMode: AgentSpeedMode? = nil,
        initialPrompt: String? = nil
    ) {
        self.providerId = providerId
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.planModeEnabled = planModeEnabled
        self.model = model
        self.effort = effort
        self.speedMode = speedMode
        self.initialPrompt = initialPrompt
    }
}
