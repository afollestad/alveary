import AgentCLIKit
import Foundation

struct AgentCLIKitHostServices: Sendable {
    let runtime: AgentCLIKit.DefaultAgentRuntime
    let sessionStore: AgentCLIKit.JSONFileAgentSessionStore
    let providerDetector: AgentCLIKit.AgentProviderDetector
    let providerRegistry: AgentCLIKit.AgentProviderRegistry
    let claudeConfigStore: AgentCLIKit.ClaudeConfigStore
    let claudeProviderSetup: AgentCLIKit.ClaudeProviderSetup
    let interactionStore: AgentCLIKit.InMemoryAgentInteractionStore
    let approvalPolicyStore: AgentCLIKit.InMemoryAgentApprovalPolicyStore
    let claudeApprovalPolicyStore: AgentCLIKit.ClaudeApprovalPolicyStore
    let contextWindowCache: AgentCLIKit.JSONAgentModelContextWindowCache
    let hostAdapter: AgentCLIKitHostAdapter
}

struct AgentCLIKitHostAdapter: Sendable {
    func conversationId(_ rawValue: String) -> AgentCLIKit.AgentConversationID {
        AgentCLIKit.AgentConversationID(rawValue: rawValue)
    }

    func providerId(_ rawValue: String) -> AgentCLIKit.AgentProviderID? {
        AgentCLIKit.AgentProviderID(rawValue: rawValue)
    }

    func spawnConfig(from config: AgentSpawnConfig) throws -> AgentCLIKit.AgentSpawnConfig {
        guard let providerId = providerId(config.providerId) else {
            throw AgentCLIKitHostAdapterError.unsupportedProvider(config.providerId)
        }
        return AgentCLIKit.AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: URL(fileURLWithPath: config.workingDirectory, isDirectory: true),
            model: config.model,
            effort: config.effort,
            permissionMode: config.permissionMode,
            initialPrompt: config.initialPrompt
        )
    }
}

enum AgentCLIKitHostAdapterError: Error, Equatable {
    case unsupportedProvider(String)
}

struct AgentCLIKitShellRunnerAdapter: AgentCLIKit.ShellRunning {
    let shellRunner: any ShellRunner

    func run(_ command: AgentCLIKit.ShellCommand) async throws -> AgentCLIKit.ShellCommandResult {
        let result = try await shellRunner.run(
            executable: command.executable,
            args: command.arguments,
            in: command.workingDirectory?.path,
            options: ShellRunOptions(environment: command.environment.isEmpty ? nil : command.environment)
        )
        return AgentCLIKit.ShellCommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}

struct AgentCLIKitDeferredHookDecisionProvider: AgentCLIKit.ClaudeHookDecisionProviding {
    func decision(
        for request: AgentCLIKit.ClaudeHookRequest,
        interactionId: AgentCLIKit.AgentInteractionID
    ) async -> AgentCLIKit.ClaudeHookDecision {
        .deferDecision
    }
}
