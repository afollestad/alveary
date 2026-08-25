import AgentCLIKit
import Foundation

/// Claude provider setup, and the auth probe its readiness gate runs on.
///
/// Separate from `AppComponent.swift` because that file sits against SwiftLint's `file_length`
/// threshold, and because the probe's wiring needs more explanation than a one-line registration.
@MainActor
extension AppComponent {
    /// The Claude setup service every readiness gate, trust check, and host service shares.
    ///
    /// Demo mode gets the probe-less initializer, which reports ready with no diagnostics, so a demo
    /// build neither spawns the CLI nor shows the developer's real sign-in state.
    var agentCLIKitProviderSetup: AgentCLIKit.ClaudeProviderSetup {
        return shared {
            demoClaudeProviderSetup ?? AgentCLIKit.ClaudeProviderSetup(
                configStore: agentCLIKitClaudeConfigStore,
                authProbe: agentCLIKitClaudeAuthProbe
            )
        }
    }

    /// Probe behind Claude setup readiness.
    ///
    /// A Finder-launched app inherits a bare `PATH`, so the spawn gets `ExecutableSearchPath`'s
    /// augmented one. The executable comes from `executablePathResolver` rather than AgentCLIKit's
    /// own detector-backed resolver, because that one re-runs `which` *and* `claude --version` on
    /// every call; this one caches a hit for the process lifetime, so a discovery refresh pays for
    /// the probe's own spawn and nothing more.
    var agentCLIKitClaudeAuthProbe: AgentCLIKit.ClaudeAuthProbe {
        return shared {
            AgentCLIKit.ClaudeAuthProbe(
                shellRunner: agentCLIKitShellRunner,
                environment: ["PATH": ExecutableSearchPath.augmentedPath(ProcessInfo.processInfo.environment["PATH"])],
                executablePath: { [executablePathResolver] in
                    guard let executableName = AgentCLIKit.ClaudeProviderDefinition.definition.executableNames.first else {
                        return nil
                    }
                    return await executablePathResolver.resolveExecutablePath(for: executableName)
                }
            )
        }
    }

    var providerSignInService: ProviderSignInService {
        return shared {
            ProviderSignInService(
                agentRegistry: agentRegistry,
                discoveryService: cachedAgentProviderDiscoveryService,
                settingsService: settingsService
            )
        }
    }
}
