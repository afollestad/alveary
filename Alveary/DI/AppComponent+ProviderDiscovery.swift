import AgentCLIKit
import Foundation

/// Discovery has shorter process budgets than provider turns, so cold or wedged CLI probes cannot monopolize a readiness check.
@MainActor
extension AppComponent {
    var agentCLIKitProviderDiscoveryService: any AgentCLIKit.AgentProviderDiscoveryService {
        return shared {
            let runner = AgentProviderDiscoveryShellRunner(shellRunner: shellRunner)
            let detector = AgentCLIKit.AgentProviderDetector(shellRunner: runner)
            let resolver = AgentCLIKit.DefaultAgentProviderExecutableResolver(detector: detector)
            // Model catalogs resolve their own executable, and capabilities run a separate feature probe.
            // Both need the same bounded runner; bounding only the outer detector leaves those reads unbounded.
            let configuration = AgentCLIKit.CodexProviderAdapter.Configuration(
                requestTimeout: 5,
                probeTimeout: 5,
                shutdownTimeout: 1,
                featureSupportChecker: AgentCLIKit.DefaultCodexFeatureSupportChecker(shellRunner: runner),
                executableResolver: resolver
            )
            return AgentCLIKit.DefaultAgentProviderDiscoveryService(
                providerRegistry: agentCLIKitProviderRegistry,
                executableDetector: detector,
                projectTrustService: agentCLIKitProjectTrustService,
                providerSetups: [
                    discoveryClaudeProviderSetup(runner: runner, resolver: resolver),
                    agentCLIKitCodexProviderSetup
                ],
                enablementSource: SettingsAgentProviderEnablementSource(settingsService: settingsService),
                modelOptionSource: AgentCLIKit.DefaultAgentModelOptionSource(
                    codexSource: AgentCLIKit.CodexAppServerModelOptionSource(configuration: configuration)
                ),
                capabilitySource: AgentCLIKit.DefaultAgentProviderCapabilitySource(
                    codexSource: AgentCLIKit.CodexProviderCapabilitySource(configuration: configuration)
                )
            )
        }
    }

    /// The provider discovery every thread-creation path should reach for; the uncached service
    /// above is its probe and nothing else should call it directly. See `Alveary/Services/Agent/AGENTS.md`.
    var cachedAgentProviderDiscoveryService: CachingAgentProviderDiscoveryService {
        return shared {
            CachingAgentProviderDiscoveryService(base: agentCLIKitProviderDiscoveryService)
        }
    }

    /// Discovery must not join the shared auth resolver's pending lookup: an inherited pipe held by a login-shell
    /// descendant can outlive its parent timeout. Keep both resolution and auth on the bounded process-group runner.
    private func discoveryClaudeProviderSetup(
        runner: AgentProviderDiscoveryShellRunner,
        resolver: AgentCLIKit.DefaultAgentProviderExecutableResolver
    ) -> AgentCLIKit.ClaudeProviderSetup {
        if let demoClaudeProviderSetup {
            return demoClaudeProviderSetup
        }
        return AgentCLIKit.ClaudeProviderSetup(
            configStore: agentCLIKitClaudeConfigStore,
            authProbe: AgentCLIKit.ClaudeAuthProbe(
                shellRunner: runner,
                environment: ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])],
                executablePath: {
                    await resolver.resolvedExecutablePath(for: AgentCLIKit.ClaudeProviderDefinition.definition)
                }
            )
        )
    }
}
