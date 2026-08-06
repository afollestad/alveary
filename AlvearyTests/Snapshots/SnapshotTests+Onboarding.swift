import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testOnboardingOverlayChecking() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .checking,
                .githubCLI: .checking,
                .claude: .checking,
                .codex: .checking
            ]),
            size: CGSize(width: 760, height: 660),
            named: "onboarding_overlay_checking"
        )
    }

    func testOnboardingOverlayMissing() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .missing(error: nil),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 660),
            named: "onboarding_overlay_missing"
        )
    }

    func testOnboardingOverlayInstalling() {
        assertMacSnapshot(
            onboardingOverlay(
                states: [
                    .commandLineTools: .installed(detail: "git version 2.51.0"),
                    .githubCLI: .installing,
                    .claude: .missing(error: nil),
                    .codex: .missing(error: nil)
                ],
                activeInstall: .githubCLI
            ),
            size: CGSize(width: 760, height: 660),
            named: "onboarding_overlay_installing"
        )
    }

    func testOnboardingOverlayFailed() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .missing(error: "`brew install gh` finished, but `gh` could not be found."),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 660),
            named: "onboarding_overlay_failed"
        )
    }

    func testOnboardingOverlayCommandLineToolsMissing() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .missing(error: nil),
                .githubCLI: .missing(error: nil),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 660),
            named: "onboarding_overlay_command_line_tools_missing"
        )
    }

    func testOnboardingOverlayFailedRequiredRowsShowManualInstallGuidance() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .missing(
                    error: "The Command Line Tools installer did not finish in time."
                ),
                .githubCLI: .missing(
                    error: "Could not reach GitHub to download the GitHub CLI. Install it manually from https://cli.github.com."
                ),
                .claude: .missing(error: "installer failed"),
                .codex: .missing(error: nil)
            ]),
            size: CGSize(width: 760, height: 760),
            named: "onboarding_overlay_failed_manual_guidance"
        )
    }

    func testOnboardingOverlayReadyToContinue() {
        assertMacSnapshot(
            onboardingOverlay(states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .installed(detail: "/Users/alveary/.codex/bin/codex")
            ]),
            size: CGSize(width: 760, height: 660),
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

    func testOnboardingOverlayGitHubNotConnected() {
        assertMacSnapshot(
            onboardingOverlay(states: installedRequiredStates, gitHubAuthState: .notConnected),
            size: CGSize(width: 760, height: 700),
            named: "onboarding_overlay_github_not_connected"
        )
    }

    func testOnboardingOverlayGitHubDeviceCode() {
        let deviceCode = GitHubDeviceCode(
            code: "ABCD-1234",
            verificationURL: URL(string: "https://github.com/login/device") ?? URL(fileURLWithPath: "/")
        )
        assertMacSnapshot(
            onboardingOverlay(
                states: installedRequiredStates,
                gitHubAuthState: .connecting(deviceCode: deviceCode)
            ),
            size: CGSize(width: 760, height: 700),
            named: "onboarding_overlay_github_device_code"
        )
    }

    func testOnboardingOverlayGitHubConnectFailed() {
        assertMacSnapshot(
            onboardingOverlay(
                states: installedRequiredStates,
                gitHubAuthState: .failed(message: "GitHub authentication did not complete.")
            ),
            size: CGSize(width: 760, height: 700),
            named: "onboarding_overlay_github_connect_failed"
        )
    }

    private var installedRequiredStates: [OnboardingDependency: OnboardingDependencyViewState] {
        [
            .commandLineTools: .installed(detail: "git version 2.51.0"),
            .githubCLI: .installed(detail: "gh version 2.89.0"),
            .claude: .missing(error: nil),
            .codex: .missing(error: nil)
        ]
    }

    private func onboardingOverlay(
        states: [OnboardingDependency: OnboardingDependencyViewState],
        activeInstall: OnboardingDependency? = nil,
        gitHubAuthState: OnboardingGitHubAuthState? = nil
    ) -> some View {
        let viewModel = OnboardingViewModel(
            settingsService: InMemorySettingsService(),
            dependencyService: SnapshotOnboardingDependencyService(),
            // Only supplied when a snapshot exercises the connect section; `showsGitHubConnect`
            // stays false without a CLI, which is what the other baselines want.
            gitHubCLI: gitHubAuthState == nil ? nil : SnapshotGitHubCLIService(),
            openURL: { _ in }
        )
        viewModel.setPresentationForTesting(
            isPresented: true,
            states: states,
            activeInstall: activeInstall
        )
        if let gitHubAuthState {
            viewModel.gitHubAuthState = gitHubAuthState
        }
        return AppOnboardingOverlay(viewModel: viewModel)
    }
}

@MainActor
private final class SnapshotGitHubCLIService: GitHubCLIService, @unchecked Sendable {
    func checkInstalled() async -> String? { "gh version 2.89.0" }
    func isAuthenticated() async -> Bool { false }
    func authenticate() async throws -> GitHubDeviceCode { throw GitHubError.authParseFailed }
    func awaitAuthentication() async throws -> Bool { false }
    func cancelAuthentication() {}
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
