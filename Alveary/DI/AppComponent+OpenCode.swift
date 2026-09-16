import AgentCLIKit
import Foundation

/// Setup and models share one bounded OpenCode probe; runtime sessions retain their own server lifetimes.
@MainActor
extension AppComponent {
    var agentCLIKitOpenCodeDiscoveryProbe: AgentCLIKit.OpenCodeDiscoveryProbe {
        return shared {
            let runner = AgentHarnessDiscoveryShellRunner(shellRunner: shellRunner)
            let detector = AgentCLIKit.AgentHarnessDetector(shellRunner: runner)
            return AgentCLIKit.OpenCodeDiscoveryProbe(
                configuration: AgentCLIKit.OpenCodeServerConfiguration(
                    executablePath: "/usr/bin/env",
                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    environment: ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])],
                    startupTimeout: 5, requestTimeout: 5, shutdownTimeout: 1
                ),
                executableResolver: AgentCLIKit.DefaultAgentHarnessExecutableResolver(detector: detector)
            )
        }
    }

    var agentCLIKitOpenCodeHarnessSetup: AgentCLIKit.OpenCodeHarnessSetup {
        return shared { AgentCLIKit.OpenCodeHarnessSetup(probe: agentCLIKitOpenCodeDiscoveryProbe) }
    }

    var agentCLIKitOpenCodeConfigStore: AgentCLIKit.OpenCodeConfigStore {
        return shared { AgentCLIKit.OpenCodeConfigStore() }
    }

    var agentCLIKitOpenCodeHarnessConfiguration: AgentCLIKit.OpenCodeHarnessAdapter.Configuration {
        AgentCLIKit.OpenCodeHarnessAdapter.Configuration(
            environment: ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])],
            sessionApprovalPolicyStore: agentCLIKitClaudeApprovalPolicyStore
        )
    }
}
