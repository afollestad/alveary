import AgentCLIKit
import Foundation

/// Rejects unsupported saved settings before runtime replacement or an outbound side effect.
enum HarnessRequestValidation {
    static func validate(_ config: AgentSpawnConfig) throws {
        // Existing harnesses can negotiate newer features during discovery. OpenCode's excluded
        // workflows stay disabled independently of a restored setting or a caller-supplied flag.
        guard config.harnessId == "opencode" else { return }
        let policy = HarnessFeaturePolicy.declared(harnessID: config.harnessId)
        if config.initialGoal != nil && !policy.supportsGoalMode {
            throw AgentError.spawnFailed("This harness does not support goals. Choose a supported harness explicitly.")
        }
        if config.speedMode == .fast && !policy.supportsSpeedMode {
            throw AgentError.spawnFailed("This harness does not support Fast mode. Select Standard before continuing.")
        }
        if config.planModeEnabled == true && !policy.supportsPlanMode {
            throw AgentError.spawnFailed("This harness does not support Plan mode.")
        }
    }

    /// A native-default model is intentionally opaque; optional model features require an explicit discovered selection.
    static func validateOpenCodeModel(
        model: String?, effort: String?, hasImages: Bool, status: AgentHarnessStatus?
    ) throws {
        let selection = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExplicit = selection != nil && selection != "" && selection != AppSettings.defaultModelValue
        let option = status?.modelOptions.first { $0.model != nil && ($0.id == selection || $0.model == selection) }
        if isExplicit && option == nil {
            throw AgentError.spawnFailed("The selected OpenCode model is unavailable. Refresh harness discovery and select an available model.")
        }
        if let effort,
           option?.supportedEffortOptions.contains(where: { $0.value == effort }) != true {
            throw AgentError.spawnFailed("The selected OpenCode model does not support reasoning option \(effort). Select a supported option.")
        }
        let policy = HarnessFeaturePolicy(harnessID: "opencode", status: status, selectedModel: model)
        if hasImages && !policy.supportsLocalImageInput {
            throw AgentError.spawnFailed("Select a discovered OpenCode model that supports images before sending images or app shots.")
        }
    }
}
