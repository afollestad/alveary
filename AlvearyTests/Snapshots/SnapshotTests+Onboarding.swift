import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testOnboardingOverlayChecking() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .githubCLI: .checking,
                .claude: .checking,
                .codex: .checking
            ]),
            size: CGSize(width: 760, height: 560),
            named: "onboarding_overlay_checking"
        )
    }

    func testOnboardingOverlayMissing() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .githubCLI: .missing(error: nil),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 560),
            named: "onboarding_overlay_missing"
        )
    }

    func testOnboardingOverlayInstalling() {
        assertMacSnapshot(
            onboardingOverlay(
                states: [
                    .githubCLI: .installing,
                    .claude: .missing(error: nil),
                    .codex: .missing(error: nil)
                ],
                activeInstall: .githubCLI
            ),
            size: CGSize(width: 760, height: 560),
            named: "onboarding_overlay_installing"
        )
    }

    func testOnboardingOverlayFailed() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .githubCLI: .missing(error: "`brew install gh` finished, but `gh` could not be found."),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 560),
            named: "onboarding_overlay_failed"
        )
    }

    func testOnboardingOverlayReadyToContinue() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .installed(detail: "/Users/alveary/.codex/bin/codex")
            ]),
            size: CGSize(width: 760, height: 560),
            named: "onboarding_overlay_ready_to_continue"
        )
    }

    func testOnboardingInstallButtonFocusedAndPressed() {
        let view = VStack(spacing: 12) {
            AppOnboardingDependencyCard(
                dependency: .claude,
                state: .missing(error: nil),
                isInstallEnabled: true,
                interactionState: .focused,
                onInstall: {}
            )
            AppOnboardingDependencyCard(
                dependency: .codex,
                state: .missing(error: nil),
                isInstallEnabled: true,
                interactionState: .pressed,
                onInstall: {}
            )
        }
        .padding(24)

        assertMacSnapshot(
            view,
            size: CGSize(width: 520, height: 220),
            named: "onboarding_install_button_focused_pressed"
        )
    }

    private func onboardingOverlay(
        states: [OnboardingDependency: OnboardingDependencyViewState],
        activeInstall: OnboardingDependency? = nil
    ) -> some View {
        let viewModel = OnboardingViewModel(
            settingsService: InMemorySettingsService(),
            dependencyService: SnapshotOnboardingDependencyService()
        )
        viewModel.setPresentationForTesting(
            isPresented: true,
            states: states,
            activeInstall: activeInstall
        )
        return AppOnboardingOverlay(viewModel: viewModel)
    }
}

@MainActor
private final class SnapshotOnboardingDependencyService: OnboardingDependencyService, @unchecked Sendable {
    func status(for dependency: OnboardingDependency) async -> OnboardingDependencyStatus {
        OnboardingDependencyStatus(dependency: dependency, state: .missing)
    }

    func install(_ dependency: OnboardingDependency) async throws -> OnboardingDependencyStatus {
        OnboardingDependencyStatus(dependency: dependency, state: .missing)
    }
}
