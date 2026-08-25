import AgentCLIKit
import Foundation

/// Runs a provider's CLI sign-in in a live terminal tab and refreshes provider readiness afterwards.
///
/// The command is interactive — it opens a browser and waits — so it cannot be captured through
/// `ShellRunner`. It launches as `kind: .projectAction` rather than `.shell`: the tab's injected
/// command is what has to report completion, and `TerminalManager` tracks that only for a project
/// action. The cost is that a sign-in counts toward the toolbar's running-project-action state, which
/// is honest — it *is* a command the user started and is waiting on.
///
/// `TerminalManager` is passed per call rather than stored, because it is `ContentView`-owned
/// `@State` shared through the environment, not an app-scoped dependency.
@MainActor
@Observable
final class ProviderSignInService {
    /// The provider whose sign-in has not yet been confirmed, if any.
    private(set) var pendingProviderID: String?

    private let agentRegistry: AgentRegistry
    private let discoveryService: CachingAgentProviderDiscoveryService
    private let settingsService: SettingsService
    private let launchBuilder: TerminalLaunchBuilder
    private var pendingSessionID: UUID?

    init(
        agentRegistry: AgentRegistry,
        discoveryService: CachingAgentProviderDiscoveryService,
        settingsService: SettingsService,
        launchBuilder: TerminalLaunchBuilder = TerminalLaunchBuilder()
    ) {
        self.agentRegistry = agentRegistry
        self.discoveryService = discoveryService
        self.settingsService = settingsService
        self.launchBuilder = launchBuilder
    }

    /// The sign-in command for a provider, or `nil` when the registry defines none.
    ///
    /// Callers gate their Sign In affordance on this rather than assuming every provider has one.
    func signInCommand(for providerID: String) -> String? {
        agentRegistry.agent(for: providerID)?.signInCommand
    }

    /// Opens a terminal tab running the provider's sign-in command.
    ///
    /// Returns `false` when the provider defines no sign-in command, so a caller that reached here
    /// anyway opens no empty tab.
    @discardableResult
    func startSignIn(providerID: String, terminalManager: TerminalManager) -> Bool {
        guard let agent = agentRegistry.agent(for: providerID),
              let command = agent.signInCommand else {
            return false
        }

        // Home, not a project: signing in is account-wide and must not imply a project context.
        let currentDirectory = launchBuilder.homeDirectory()
        pendingSessionID = terminalManager.createSession(
            kind: .projectAction,
            title: "Sign in to \(agent.name)",
            currentDirectory: currentDirectory,
            maxSessions: ProjectActionTerminalPresentation.maxSessions(settings: settingsService.current),
            launchConfiguration: launchBuilder.projectAction(command: command, currentDirectory: currentDirectory)
        )
        pendingProviderID = providerID
        return true
    }

    /// Refreshes readiness once the sign-in tab's command exits.
    ///
    /// Driven by `TerminalManager.runningProjectActionSessionIDs`, which the app root already
    /// observes, so this needs no completion callback of its own.
    func handleRunningProjectActionSessionIDsChange(_ runningSessionIDs: Set<UUID>) {
        guard let sessionID = pendingSessionID, !runningSessionIDs.contains(sessionID) else {
            return
        }
        pendingSessionID = nil
        refreshProviderReadiness()
    }

    /// One safety-net refresh, for a sign-in whose tab is already gone.
    ///
    /// Catches the user who closed the tab and finished in their own Terminal instead. Two gates keep
    /// discovery's `which` / login-shell / `--version` fan-out off ordinary app switches: nothing runs
    /// unless a sign-in is pending, and nothing runs while the tab is still live, because the browser
    /// round trip happens *before* the command exits and `handleRunningProjectActionSessionIDsChange`
    /// is the reliable trigger for that. Tracking then stops whatever this finds — a user who came
    /// back without finishing will not be caught by the next activation either, and staying pending
    /// would put that fan-out on every activation for the rest of the session. The Agents settings
    /// screen and system wake each invalidate on their own, so a later sign-in is still picked up.
    func handleAppDidBecomeActive() {
        guard pendingProviderID != nil, pendingSessionID == nil else {
            return
        }
        refreshProviderReadiness(stopsTrackingRegardless: true)
    }
}

private extension ProviderSignInService {
    /// Discards the cached snapshot, rebuilds it, and stops tracking once the provider reports ready.
    /// Staying pending while it is not lets the one bounded activation retry try again, which is what
    /// a user who abandoned the browser and came back to finish needs.
    ///
    /// `stopsTrackingRegardless` gives up before the answer arrives, for the caller that has no
    /// further trigger left to offer. The refresh still runs, so the snapshot every other readiness
    /// gate reads is fresh either way.
    func refreshProviderReadiness(stopsTrackingRegardless: Bool = false) {
        guard let providerID = pendingProviderID else {
            return
        }
        if stopsTrackingRegardless {
            pendingProviderID = nil
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await discoveryService.invalidate()
            await discoveryService.warm()
            let statuses = await discoveryService.providerStatuses(projectURL: nil)
            guard pendingProviderID == providerID,
                  statuses.values.first(where: { $0.providerId.rawValue == providerID })?.isSetupReady == true else {
                return
            }
            pendingProviderID = nil
        }
    }
}
