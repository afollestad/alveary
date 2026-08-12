#if DEBUG
import AppKit
import Foundation

/// Entry point for the DEBUG-only screenshot mode.
///
/// `prepareIfNeeded()` runs from `AlvearyApp.init`, right after `AppDI.component` resolves and
/// before any scene body evaluates. That ordering is load-bearing: `OnboardingViewModel` reads
/// `hasCompletedOnboarding` once at construction, so setting it here is what keeps a
/// wiped-every-launch profile from facing the onboarding flow on every run, and every `@Query`
/// view sees a populated store on its first evaluation.
@MainActor
enum DemoMode {
    static func prepareIfNeeded() {
        let component = AppDI.component
        let storageProfile = component.storageProfile
        guard storageProfile.isDemo else {
            return
        }

        // `autoTrustProjects` deliberately stays false: auto-trust writes through to the real
        // `~/.claude.json`, which the storage profile does not isolate. Seeded threads set
        // `hasCompletedInitialSetup` instead, so the trust gate never fires.
        component.settingsService.update { settings in
            settings.hasCompletedOnboarding = true
        }

        do {
            try DemoDataSeeder.seed(
                into: component.modelContainer.mainContext,
                attachmentsDirectory: storageProfile.conversationAttachmentsDirectory
            )
        } catch {
            assertionFailure("Demo seeding failed: \(error.localizedDescription)")
            return
        }

        applyFakeActivity(component)
    }

    /// Relaunches the app into — or out of — demo mode.
    ///
    /// `NSWorkspace`, not `Process`: assigning `Process.environment` *replaces* the environment
    /// rather than merging, which would strip `PATH`/`HOME`/`SHELL` from the child and break
    /// provider detection, `gh`, and the terminal pane. It also launches the raw executable, which
    /// leaves the child's TCC responsible-process chain pointing at the dying parent. This route
    /// matches `run.sh --demo`, which uses `open --env` — likewise a LaunchServices launch.
    static func relaunch(inDemoMode enabled: Bool, onFailure: @escaping @MainActor (String) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = Self.relaunchEnvironment(inDemoMode: enabled)
        // Required: without it LaunchServices just activates the instance that is about to die.
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                guard let error else {
                    // Terminate only after the successor is confirmed launched.
                    NSApp.terminate(nil)
                    return
                }
                onFailure(error.localizedDescription)
            }
        }
    }

    /// The environment handed to the successor, which `NSWorkspace` *merges* into the one it
    /// inherits rather than swapping in.
    ///
    /// Both directions therefore have to name the key: an empty dictionary looks like it clears the
    /// variable and cannot, so a demo instance would pass its own `ALVEARY_DEMO_MODE=1` down and
    /// the relaunch meant to leave demo mode would come back up in it. `detectKind` reads the
    /// explicit "0" as off.
    static func relaunchEnvironment(inDemoMode enabled: Bool) -> [String: String] {
        [AppRuntimeProfile.demoEnvironmentKey: enabled ? "1" : "0"]
    }

    /// Status dots and the in-flight tool spinner, without a provider runtime.
    ///
    /// `updateStatus(_:for:)` is declared on `DefaultAgentsManager`, not the `AgentsManager`
    /// protocol, so this has to go through the concrete registration.
    private static func applyFakeActivity(_ component: AppComponent) {
        let manager = component.defaultAgentsManager
        manager.updateStatus(.busy, for: DemoData.tripSharingConversation)
        manager.updateStatus(.waitingForUser, for: DemoData.flakyMapTestsConversation)
    }
}
#endif
