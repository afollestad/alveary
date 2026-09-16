import AgentCLIKit

@MainActor
extension AppComponent {
    var agentCLIKitOneShotPromptRunner: AgentCLIKit.DefaultAgentOneShotPromptRunner {
        return shared {
            let executableResolver = AgentCLIKit.DefaultAgentHarnessExecutableResolver(detector: agentCLIKitHarnessDetector)
            return AgentCLIKit.DefaultAgentOneShotPromptRunner(
                adapterSet: AgentCLIKit.AgentHarnessAdapterSet.default(
                    claude: AgentCLIKit.ClaudeHarnessAdapter.Configuration(
                        enableHooks: false,
                        executableResolver: executableResolver
                    ),
                    codex: AgentCLIKit.CodexHarnessAdapter.Configuration(
                        executableResolver: executableResolver
                    ),
                    opencode: AgentCLIKit.OpenCodeHarnessAdapter.Configuration(
                        executableResolver: executableResolver
                    )
                ),
                shellRunner: AgentCLIKit.ProcessShellRunner()
            )
        }
    }
}
