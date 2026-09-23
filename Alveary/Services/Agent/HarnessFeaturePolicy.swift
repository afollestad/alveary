import AgentCLIKit
import Foundation

/// Keeps UI affordances and execution admission aligned without inventing capabilities while discovery is pending.
struct HarnessFeaturePolicy: Sendable {
    let harnessID: String
    private let capabilities: AgentHarnessCapabilities?
    private let model: AgentModelOption?

    init(harnessID: String, status: AgentHarnessStatus?, selectedModel: String? = nil) {
        self.harnessID = harnessID
        let status = status?.harnessId.rawValue == harnessID ? status : nil
        capabilities = status?.definition?.capabilities
        if harnessID == "opencode" {
            let selection = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            model = status?.modelOptions.first {
                $0.model != nil && selection != nil && ($0.id == selection || $0.model == selection)
            }
        } else {
            model = AgentModelOptionSelection.option(in: status?.modelOptions ?? [], matching: selectedModel)
        }
    }

    private init(harnessID: String, capabilities: AgentHarnessCapabilities?) {
        self.harnessID = harnessID
        self.capabilities = capabilities
        model = nil
    }

    /// Execution guards can use stable adapter contracts; model-dependent features still need discovered metadata.
    static func declared(harnessID: String) -> HarnessFeaturePolicy {
        let capabilities = AgentHarnessRegistry.builtInDefinitions.first { $0.id.rawValue == harnessID }?.capabilities
        return HarnessFeaturePolicy(harnessID: harnessID, capabilities: capabilities)
    }

    var hasCapabilities: Bool { capabilities != nil }
    var supportsGoalMode: Bool { capabilities?.supportsGoalMode == true }
    var supportsExistingSessionGoalStart: Bool { capabilities?.supportsExistingSessionGoalStart == true }
    var supportsSpeedMode: Bool { capabilities?.supportsSpeedMode == true }
    var supportsPlanMode: Bool { capabilities?.supportsPlanMode == true }
    var supportsMidTurnSteering: Bool { capabilities?.supportsMidTurnSteering == true }
    var supportsContextCompaction: Bool { capabilities?.supportsContextCompaction == true }
    var supportsReasoning: Bool { capabilities != nil && model?.supportedEffortOptions.isEmpty == false }
    var supportsReadOnlyOneShotPrompts: Bool { capabilities?.supportsReadOnlyOneShotPrompts == true }
    var supportsIsolatedReviewWorkers: Bool {
        supportsReadOnlyOneShotPrompts && Self.supportsIsolatedReviewWorkers(harnessID: harnessID)
    }
    var supportsNativeBackgroundTasks: Bool { capabilities != nil && harnessID != "opencode" }
    var supportsAdvancedSubagentControl: Bool { capabilities?.supportsSubagents == true && harnessID != "opencode" }
    var supportsRawTranscriptLog: Bool { Self.supportsRawTranscriptLog(harnessID: harnessID) }

    var supportsLocalImageInput: Bool {
        guard capabilities?.supportsLocalImageInput == true else { return false }
        return harnessID != "opencode" || model?.metadata[OpenCodeModelMetadata.supportsImageInput] == .bool(true)
    }

    var supportsAppShots: Bool { capabilities != nil && (harnessID == "claude" || supportsLocalImageInput) }

    /// Utility execution can check its adapter contract before invoking discovery, trust setup, or a process.
    static func supportsReadOnlyOneShotPrompts(harnessID: String) -> Bool {
        AgentHarnessRegistry.builtInDefinitions.first { $0.id.rawValue == harnessID }?.capabilities.supportsReadOnlyOneShotPrompts == true
    }

    /// The thread's persisted isolation, narrowed to what the harness honors. The SDK fails a launch that asks for
    /// more rather than running unisolated, so a harness that honors nothing launches exactly as before.
    @MainActor
    static func launchIsolation(for thread: AgentThread?, harnessID: String) -> AgentIntegrationIsolation {
        let supported = AgentHarnessRegistry.builtInDefinitions.first { $0.id.rawValue == harnessID }?
            .capabilities.supportedIntegrationIsolation ?? []
        return (thread?.integrationIsolation ?? []).intersection(supported)
    }

    /// Reviews require verified isolation flags or an SDK-owned disposable profile, in addition to the one-shot contract.
    static func supportsIsolatedReviewWorkers(harnessID: String) -> Bool {
        supportsReadOnlyOneShotPrompts(harnessID: harnessID)
    }

    static func supportsRawTranscriptLog(harnessID: String) -> Bool {
        harnessID == "claude" || harnessID == "codex"
    }

    static func unavailableUtilityMessage(harnessID: String) -> String {
        "\(displayName(harnessID)) does not support read-only utility prompts. Choose an available harness in Utility settings."
    }

    static func unavailableReviewMessage(harnessID: String) -> String {
        "\(displayName(harnessID)) does not support isolated review workers. Choose an available harness for this reviewer."
    }

    private static func displayName(_ harnessID: String) -> String {
        harnessID == "opencode" ? "OpenCode" : harnessID
    }
}
