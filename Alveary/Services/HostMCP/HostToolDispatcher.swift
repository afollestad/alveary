import AgentCLIKit
import Foundation

/// Routes one `alveary_host` tool call to the feature that owns its name.
///
/// AgentCLIKit injects a single handler per runtime, so this is where Alveary's features
/// merge. Names are unique across features; the registration-time check below fails fast in
/// debug, and AgentCLIKit rejects duplicates again when the server registers.
@MainActor
final class HostToolDispatcher {
    /// Features resolve on the first call, never at construction.
    ///
    /// This dispatcher is built *inside* the agent runtime it dispatches for — `hostToolHandling`
    /// is a constructor argument of `DefaultAgentRuntime` — so a feature that depends on
    /// `AgentsManager` would otherwise recurse through the runtime and overflow the stack during
    /// DI. `ThreadHostToolService` does exactly that, by way of `ThreadLifecycleService`. By the
    /// time any tool call arrives a provider process is running, so the graph is complete.
    private let makeFeatures: () -> [any HostToolFeature]
    private var resolvedFeaturesByToolName: [String: any HostToolFeature]?

    convenience init(features: [any HostToolFeature]) {
        self.init(features: { features })
    }

    init(features: @escaping () -> [any HostToolFeature]) {
        makeFeatures = features
    }

    func handle(
        context: AgentCLIKit.AgentHostToolCallContext,
        call: AgentCLIKit.AgentHostToolCall
    ) async -> AgentCLIKit.AgentHostToolResult {
        guard let feature = featuresByToolName()[call.name] else {
            return AgentCLIKit.AgentHostToolResult(
                text: "This Alveary tool is not available.",
                isError: true
            )
        }
        return await feature.handle(context: context, call: call)
    }

    /// Adapter handed to `AgentCLIKit.DefaultAgentRuntime`.
    var handling: AgentCLIKit.AgentHostToolHandling {
        let dispatcher = self
        return AgentCLIKit.AgentHostToolHandling { context, call in
            await dispatcher.handle(context: context, call: call)
        }
    }

    private func featuresByToolName() -> [String: any HostToolFeature] {
        if let resolvedFeaturesByToolName {
            return resolvedFeaturesByToolName
        }
        let features = makeFeatures()
        if let collision = Self.duplicateToolName(in: features.map(\.hostToolNames)) {
            preconditionFailure("Duplicate alveary_host tool name across features: \(collision)")
        }
        var featuresByToolName: [String: any HostToolFeature] = [:]
        for feature in features {
            for toolName in feature.hostToolNames {
                featuresByToolName[toolName] = feature
            }
        }
        resolvedFeaturesByToolName = featuresByToolName
        return featuresByToolName
    }

    /// The first name claimed by more than one feature, or `nil` when every name is unique.
    nonisolated static func duplicateToolName(in toolNameSets: [Set<String>]) -> String? {
        var seen = Set<String>()
        for toolNames in toolNameSets {
            for toolName in toolNames.sorted() where !seen.insert(toolName).inserted {
                return toolName
            }
        }
        return nil
    }
}
