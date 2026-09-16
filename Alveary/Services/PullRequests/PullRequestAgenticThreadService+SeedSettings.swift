import AgentCLIKit
import Foundation

/// Resolves persisted task settings before the launch path validates OpenCode provider/model and native variant availability.
extension PullRequestAgenticThreadService {
    /// Legacy harnesses retain fallback behavior; OpenCode choices survive until launch validation can explain an unavailable pin.
    static func resolveSeedSettings(
        settings: AppSettings,
        resolution: ThreadDefaultResolution,
        harness: String,
        modelOptions: [AgentModelOption],
        kind: Kind = .review
    ) -> SeedSettings {
        let agent = kind.agentSettings(in: settings)
        let inheritsResolution = harness == resolution.harnessID
        if harness == "opencode" {
            let model = agent.model.map(AppSettings.normalizedModelSelection) ?? (inheritsResolution ? resolution.storedThreadModel : nil)
            return SeedSettings(
                harness: harness,
                model: model == AppSettings.defaultModelValue ? nil : model,
                effort: agent.effort ?? (inheritsResolution ? resolution.effort : AppSettings.openCodeDefaultEffort),
                permissionMode: resolvedPermissionMode(agent: agent, resolution: resolution, harness: harness, inheritsResolution: inheritsResolution)
            )
        }
        let model = resolvedModel(
            agent: agent,
            resolution: resolution,
            options: modelOptions,
            inheritsResolution: inheritsResolution
        )
        let effort = resolvedEffort(
            agent: agent,
            resolution: resolution,
            options: modelOptions,
            model: model,
            inheritsResolution: inheritsResolution
        )
        let permissionMode = resolvedPermissionMode(
            agent: agent,
            resolution: resolution,
            harness: harness,
            inheritsResolution: inheritsResolution
        )
        return SeedSettings(harness: harness, model: model, effort: effort, permissionMode: permissionMode)
    }

    private static func resolvedPermissionMode(
        agent: PullRequestAgentSettings,
        resolution: ThreadDefaultResolution,
        harness: String,
        inheritsResolution: Bool
    ) -> String {
        if let requested = agent.permissionMode,
           AppSettings.supportedPermissionModes(forHarness: harness).contains(requested) {
            return requested
        }
        return inheritsResolution ? resolution.permissionMode : AppSettings.defaultPermissionMode(forHarness: harness)
    }

    private static func resolvedModel(
        agent: PullRequestAgentSettings,
        resolution: ThreadDefaultResolution,
        options: [AgentModelOption],
        inheritsResolution: Bool
    ) -> String? {
        let inherited = inheritsResolution ? resolution.storedThreadModel : nil
        guard let requested = agent.model,
              let option = AgentModelOptionSelection.option(in: options, matching: requested) else {
            return inherited
        }
        let stored = AgentModelOptionSelection.storedModelValue(for: option)
        return stored == AppSettings.defaultModelValue ? nil : stored
    }

    private static func resolvedEffort(
        agent: PullRequestAgentSettings,
        resolution: ThreadDefaultResolution,
        options: [AgentModelOption],
        model: String?,
        inheritsResolution: Bool
    ) -> String {
        let inherited = inheritsResolution ? resolution.effort : AppSettings.defaultEffortLevel
        guard let requested = agent.effort else {
            return AgentModelOptionSelection.normalizedEffort(inherited, options: options, selectedModel: model)
        }
        // An empty supported list means the harness reports no effort catalog, which is not the
        // same as rejecting the value.
        let supported = AgentModelOptionSelection.effortOptions(in: options, selectedModel: model)
        guard supported.isEmpty || supported.contains(where: { $0.value == requested }) else {
            return AgentModelOptionSelection.normalizedEffort(inherited, options: options, selectedModel: model)
        }
        return requested
    }
}
