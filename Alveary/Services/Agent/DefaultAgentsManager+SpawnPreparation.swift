import Foundation

extension DefaultAgentsManager {
    func agentConfig(config: AgentSpawnConfig, sessionId: String) -> AgentConfig {
        AgentConfig(
            providerId: config.providerId,
            sessionId: sessionId,
            workingDirectory: config.workingDirectory,
            permissionMode: config.permissionMode,
            model: config.model,
            effort: config.effort,
            initialPrompt: config.initialPrompt
        )
    }

    func preparedArguments(
        adapter: AgentAdapter,
        agentConfig: AgentConfig,
        sessionLaunch: SessionLaunchDecision,
        extraArgs: String?
    ) throws -> [String] {
        var arguments = adapter.buildArgs(config: agentConfig)
        arguments += sessionLaunch.args
        if let extraArgs, !extraArgs.isEmpty {
            arguments += try parseExtraArgs(extraArgs)
        }
        return arguments
    }

    func hookLaunchConfigIfNeeded(
        providerId: String,
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig? {
        guard providerId == "claude" else {
            return nil
        }

        return await claudeHookServer.prepareLaunch(
            permissionMode: permissionMode,
            conversationId: conversationId
        )
    }

    func mergedProviderEnvironment(
        adapter: AgentAdapter,
        agentConfig: AgentConfig,
        customEnv: [String: String]?,
        hookLaunchEnvironment: [String: String]?
    ) -> [String: String] {
        var providerEnv = adapter.envOverrides(config: agentConfig)
        if let customEnv {
            providerEnv.merge(customEnv) { _, custom in custom }
        }
        if let hookLaunchEnvironment {
            providerEnv.merge(hookLaunchEnvironment) { _, hook in hook }
        }
        return providerEnv
    }
}
