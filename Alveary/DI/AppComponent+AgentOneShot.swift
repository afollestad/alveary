import AgentCLIKit

@MainActor
extension AppComponent {
    var agentCLIKitOneShotPromptRunner: AgentCLIKit.DefaultAgentOneShotPromptRunner {
        return shared {
            let executableResolver = AgentCLIKit.DefaultAgentProviderExecutableResolver(detector: agentCLIKitProviderDetector)
            return AgentCLIKit.DefaultAgentOneShotPromptRunner(
                adapterSet: AgentCLIKit.AgentProviderAdapterSet.default(
                    claude: AgentCLIKit.ClaudeProviderAdapter.Configuration(
                        enableHooks: false,
                        executableResolver: executableResolver
                    ),
                    codex: AgentCLIKit.CodexProviderAdapter.Configuration(
                        executableResolver: executableResolver
                    )
                ),
                shellRunner: AgentCLIKit.ProcessShellRunner()
            )
        }
    }
}
