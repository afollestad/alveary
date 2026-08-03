import AgentCLIKit
import Foundation

extension DefaultAgentsManager {
    func spawnAgentCLIKitWithHostToolFallback(
        conversationId: String,
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        config: AgentSpawnConfig,
        forkSession: Bool,
        services: AgentCLIKitHostServices
    ) async throws {
        do {
            let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: forkSession, services: services)
            try await services.runtime.spawn(conversationId: runtimeConversationId, config: spawnConfig)
        } catch {
            guard HostToolFallbackClassifier.decision(for: error, config: config) == .retryWithoutHostTools else {
                throw error
            }
            await markHostToolsUnavailable(
                conversationId: conversationId,
                requiresRuntimeReplacement: false
            )
            let fallbackConfig = config.withoutHostTools()
            let spawnConfig = try await agentCLIKitSpawnConfig(
                fallbackConfig,
                forkSession: forkSession,
                services: services
            )
            try await services.runtime.spawn(conversationId: runtimeConversationId, config: spawnConfig)
        }
    }

    func freshAgentCLIKitSessionWithHostToolFallback(
        conversationId: String,
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        config: AgentSpawnConfig,
        services: AgentCLIKitHostServices
    ) async throws -> AgentSpawnConfig {
        do {
            let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: false, services: services)
            try await services.runtime.freshSession(conversationId: runtimeConversationId, config: spawnConfig)
            return config
        } catch {
            guard HostToolFallbackClassifier.decision(for: error, config: config) == .retryWithoutHostTools else {
                throw error
            }
            await markHostToolsUnavailable(
                conversationId: conversationId,
                requiresRuntimeReplacement: false
            )
            let fallbackConfig = config.withoutHostTools()
            let spawnConfig = try await agentCLIKitSpawnConfig(
                fallbackConfig,
                forkSession: false,
                services: services
            )
            try await services.runtime.freshSession(conversationId: runtimeConversationId, config: spawnConfig)
            return fallbackConfig
        }
    }

    func reconfigureAgentCLIKitWithHostToolFallback(
        conversationId: String,
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        config: AgentSpawnConfig,
        services: AgentCLIKitHostServices
    ) async throws -> (
        result: AgentCLIKit.AgentRuntimeReconfigureResult,
        effectiveConfig: AgentSpawnConfig
    ) {
        do {
            let spawnConfig = try await agentCLIKitSpawnConfig(config, forkSession: true, services: services)
            let result = try await services.runtime.reconfigure(
                conversationId: runtimeConversationId,
                config: spawnConfig
            )
            return (result, config)
        } catch {
            guard HostToolFallbackClassifier.decision(for: error, config: config) == .retryWithoutHostTools else {
                throw error
            }
            await markHostToolsUnavailable(
                conversationId: conversationId,
                requiresRuntimeReplacement: false
            )
            let fallbackConfig = config.withoutHostTools()
            let spawnConfig = try await agentCLIKitSpawnConfig(
                fallbackConfig,
                forkSession: true,
                services: services
            )
            let result = try await services.runtime.reconfigure(
                conversationId: runtimeConversationId,
                config: spawnConfig
            )
            return (result, fallbackConfig)
        }
    }

    func markHostToolsUnavailable(
        conversationId: String,
        requiresRuntimeReplacement: Bool
    ) async {
        await MainActor.run {
            let state = self.conversationState(for: conversationId)
            state.markHostToolsUnavailable(requiresRuntimeReplacement: requiresRuntimeReplacement)
        }
    }
}

enum HostToolLaunchFailure: Equatable {
    case hostToolsUnavailable
    case codexThreadJSONRPC(method: String, message: String)
    case unrelated
}

enum HostToolFallbackDecision: Equatable {
    case retryWithoutHostTools
    case propagate
}

struct HostToolFallbackClassifier {
    private static let codexThreadBootstrapMethods: Set<String> = [
        "thread/start",
        "thread/resume",
        "thread/fork"
    ]
    private static let codexHostToolPolicyMarkers = [
        AlvearyHostToolCatalog.serverName,
        "mcp_servers",
        "enabled_tools",
        "approval_mode"
    ]

    static func decision(
        for error: Error,
        config: AgentSpawnConfig
    ) -> HostToolFallbackDecision {
        decision(for: launchFailure(from: error), config: config)
    }

    static func decision(
        for failure: HostToolLaunchFailure,
        config: AgentSpawnConfig
    ) -> HostToolFallbackDecision {
        guard !config.hostTools.isEmpty else {
            return .propagate
        }
        switch failure {
        case .hostToolsUnavailable:
            return .retryWithoutHostTools
        case let .codexThreadJSONRPC(method, message):
            guard config.providerId == "codex",
                  codexThreadBootstrapMethods.contains(method),
                  explicitlyReferencesInjectedCodexHostToolPolicy(message, config: config) else {
                return .propagate
            }
            return .retryWithoutHostTools
        case .unrelated:
            return .propagate
        }
    }

    private static func launchFailure(from error: Error) -> HostToolLaunchFailure {
        if let error = error as? AgentCLIKit.AgentCLIError,
           error.code == .hostToolsUnavailable {
            return .hostToolsUnavailable
        }
        if let error = error as? AgentCLIKit.CodexAppServerError,
           case let .jsonRPCError(method, _, message) = error {
            return .codexThreadJSONRPC(method: method, message: message)
        }
        return .unrelated
    }

    private static func explicitlyReferencesInjectedCodexHostToolPolicy(
        _ message: String,
        config: AgentSpawnConfig
    ) -> Bool {
        let normalizedMessage = message.lowercased()
        let configuredServerName = config.hostToolServer.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !configuredServerName.isEmpty,
           normalizedMessage.contains(configuredServerName) {
            return true
        }
        return codexHostToolPolicyMarkers.contains(where: normalizedMessage.contains)
    }
}
