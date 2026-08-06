import XCTest

@testable import Alveary

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testFirstRunPresentsImmediatelyAndRefreshesAllStatuses() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        XCTAssertTrue(viewModel.isPresented)
        try await waitUntil("all onboarding statuses refresh") {
            service.statusRequests == [.commandLineTools, .githubCLI, .claude, .codex]
        }
        XCTAssertFalse(viewModel.canContinue)
    }

    func testContinueStaysBlockedWhenCommandLineToolsAreMissing() {
        let settings = InMemorySettingsService()
        let viewModel = OnboardingViewModel(
            settingsService: settings,
            dependencyService: OnboardingDependencyServiceFake()
        )

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .missing(error: nil),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )

        // Git is unusable without Command Line Tools, so an installed `gh` alone is not enough.
        XCTAssertFalse(viewModel.canContinue)
    }

    func testCompletedOnboardingReappearsWhenCommandLineToolsGoMissing() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        try await waitUntil("onboarding reappears once Command Line Tools are confirmed missing") {
            viewModel.isPresented
        }
    }

    func testCompletedOnboardingStaysHiddenWhileRequiredStatusIsChecking() async {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake()
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state(for: .githubCLI), .checking)
    }

    func testCompletedOnboardingReappearsWhenGitHubCLIIsConfirmedMissing() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .installed(detail: "/usr/local/bin/claude")),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        try await waitUntil("onboarding reappears after required dependency is confirmed missing") {
            viewModel.isPresented
        }
        XCTAssertEqual(service.statusRequests, [.commandLineTools, .githubCLI, .claude, .codex])
    }

    func testCompletedOnboardingDoesNotReappearWhenOnlyOptionalDependenciesAreMissing() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        try await waitUntil("required dependencies refresh") {
            service.statusRequests == [.commandLineTools, .githubCLI]
        }
        XCTAssertFalse(viewModel.isPresented)
    }

    func testAppDidBecomeActiveRefreshesRequiredStatusForCompletedHiddenOnboarding() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0"))
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.handleAppDidBecomeActive()

        try await waitUntil("required dependencies refresh after app activation") {
            service.statusRequests == [.commandLineTools, .githubCLI]
        }
        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state(for: .githubCLI), .installed(detail: "gh version 2.89.0"))
    }

    func testContinueRefreshesRequiredDependencyAndSavesCompletionOnlyWhenInstalled() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )
        viewModel.continueOnboarding()

        try await waitUntil("onboarding completion persists") {
            settings.current.hasCompletedOnboarding
        }
        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(service.statusRequests, [.commandLineTools, .githubCLI])
    }

    func testContinueCancelsOptionalInstallAndReturnsItToMissingWhenRequiredRefreshFails() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .installing,
                .codex: .missing(error: nil)
            ],
            activeInstall: .claude
        )
        viewModel.continueOnboarding()

        try await waitUntil("required dependency refresh fails") {
            service.statusRequests == [.commandLineTools, .githubCLI]
        }
        XCTAssertTrue(viewModel.isPresented)
        XCTAssertEqual(viewModel.state(for: .claude), .missing(error: nil))
        XCTAssertNil(viewModel.activeInstall)
        XCTAssertFalse(settings.current.hasCompletedOnboarding)
    }

    func testInstallShowsInstallingThenInstalledAndReenablesOtherInstalls() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(suspendedInstalls: [.claude])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .missing(error: nil),
                .githubCLI: .missing(error: nil),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )
        viewModel.install(.claude)

        try await waitUntil("optional install starts") {
            service.installRequests == [.claude]
                && viewModel.activeInstall == .claude
                && viewModel.state(for: .claude) == .installing
        }
        XCTAssertFalse(viewModel.canInstall(.codex))

        service.completeInstall(
            .claude,
            with: .success(OnboardingDependencyStatus(dependency: .claude, state: .installed(detail: "/usr/local/bin/claude")))
        )

        try await waitUntil("optional install completes") {
            viewModel.activeInstall == nil
                && viewModel.state(for: .claude) == .installed(detail: "/usr/local/bin/claude")
        }
        XCTAssertTrue(viewModel.canInstall(.codex))
    }

    func testInstallFailureReturnsDependencyToMissingWithError() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(
            installs: [.codex: .failure(OnboardingViewModelTestError(message: "installer failed"))]
        )
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .missing(error: nil),
                .githubCLI: .missing(error: nil),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )
        viewModel.install(.codex)

        try await waitUntil("optional install fails") {
            viewModel.activeInstall == nil
                && viewModel.state(for: .codex) == .missing(error: "installer failed")
        }
    }
}
