import AgentCLIKit
import Foundation

/// Discovery has shorter process budgets than harness turns, so cold or wedged CLI probes cannot monopolize a readiness check.
@MainActor
extension AppComponent {
    var agentCLIKitHarnessDiscoveryService: any AgentCLIKit.AgentHarnessDiscoveryService {
        return shared {
            let runner = AgentHarnessDiscoveryShellRunner(shellRunner: shellRunner)
            let detector = AgentCLIKit.AgentHarnessDetector(shellRunner: runner)
            let resolver = AgentCLIKit.DefaultAgentHarnessExecutableResolver(detector: detector)
            // Model catalogs resolve their own executable, and capabilities run a separate feature probe.
            // Both need the same bounded runner; bounding only the outer detector leaves those reads unbounded.
            let configuration = AgentCLIKit.CodexHarnessAdapter.Configuration(
                requestTimeout: 5,
                probeTimeout: 5,
                shutdownTimeout: 1,
                featureSupportChecker: AgentCLIKit.DefaultCodexFeatureSupportChecker(shellRunner: runner),
                executableResolver: resolver
            )
            let base = AgentCLIKit.DefaultAgentHarnessDiscoveryService(
                harnessRegistry: agentCLIKitHarnessRegistry,
                executableDetector: detector,
                projectTrustService: agentCLIKitProjectTrustService,
                harnessSetups: [
                    discoveryClaudeHarnessSetup(runner: runner, resolver: resolver),
                    agentCLIKitCodexHarnessSetup,
                    agentCLIKitOpenCodeHarnessSetup
                ],
                enablementSource: SettingsAgentHarnessEnablementSource(settingsService: settingsService),
                modelOptionSource: AgentCLIKit.DefaultAgentModelOptionSource(
                    codexSource: AgentCLIKit.CodexAppServerModelOptionSource(configuration: configuration),
                    openCodeSource: AgentCLIKit.OpenCodeModelOptionSource(probe: agentCLIKitOpenCodeDiscoveryProbe)
                ),
                capabilitySource: AgentCLIKit.DefaultAgentHarnessCapabilitySource(
                    codexSource: AgentCLIKit.CodexHarnessCapabilitySource(configuration: configuration)
                )
            )
            let environment = ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])]
            return ProjectScopedOpenCodeDiscoveryService(base: base, projectTrustService: agentCLIKitProjectTrustService) { directory in
                let probe = AgentCLIKit.OpenCodeDiscoveryProbe(
                    configuration: AgentCLIKit.OpenCodeServerConfiguration(
                        executablePath: "/usr/bin/env", workingDirectory: directory,
                        environment: environment, startupTimeout: 5, requestTimeout: 5, shutdownTimeout: 1
                    ),
                    executableResolver: resolver
                )
                return await probe.refresh()
            }
        }
    }

    /// The harness discovery every thread-creation path should reach for; the uncached service
    /// above is its probe and nothing else should call it directly. See `Alveary/Services/Agent/AGENTS.md`.
    var cachedAgentHarnessDiscoveryService: CachingAgentHarnessDiscoveryService {
        return shared {
            CachingAgentHarnessDiscoveryService(base: agentCLIKitHarnessDiscoveryService)
        }
    }

    /// Discovery must not join the shared auth resolver's pending lookup: an inherited pipe held by a login-shell
    /// descendant can outlive its parent timeout. Keep both resolution and auth on the bounded process-group runner.
    private func discoveryClaudeHarnessSetup(
        runner: AgentHarnessDiscoveryShellRunner,
        resolver: AgentCLIKit.DefaultAgentHarnessExecutableResolver
    ) -> AgentCLIKit.ClaudeHarnessSetup {
        if let demoClaudeHarnessSetup {
            return demoClaudeHarnessSetup
        }
        return AgentCLIKit.ClaudeHarnessSetup(
            configStore: agentCLIKitClaudeConfigStore,
            authProbe: AgentCLIKit.ClaudeAuthProbe(
                shellRunner: runner,
                environment: ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])],
                executablePath: {
                    await resolver.resolvedExecutablePath(for: AgentCLIKit.ClaudeHarnessDefinition.definition)
                }
            )
        )
    }
}
