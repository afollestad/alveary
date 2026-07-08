import XCTest

@testable import Alveary

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testFirstRunPresentsImmediatelyAndRefreshesAllStatuses() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        XCTAssertTrue(viewModel.isPresented)
        try await waitUntil("all onboarding statuses refresh") {
            service.statusRequests == [.githubCLI, .claude, .codex]
        }
        XCTAssertFalse(viewModel.canContinue)
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
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .installed(detail: "/usr/local/bin/claude")),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        try await waitUntil("onboarding reappears after required dependency is confirmed missing") {
            viewModel.isPresented
        }
        XCTAssertEqual(service.statusRequests, [.githubCLI, .claude, .codex])
    }

    func testCompletedOnboardingDoesNotReappearWhenOnlyOptionalDependenciesAreMissing() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.start()

        try await waitUntil("required dependency refreshes") {
            service.statusRequests == [.githubCLI]
        }
        XCTAssertFalse(viewModel.isPresented)
    }

    func testAppDidBecomeActiveRefreshesRequiredStatusForCompletedHiddenOnboarding() async throws {
        let settings = InMemorySettingsService(current: AppSettings(hasCompletedOnboarding: true))
        let service = OnboardingDependencyServiceFake(statuses: [
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0"))
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.handleAppDidBecomeActive()

        try await waitUntil("required dependency refreshes after app activation") {
            service.statusRequests == [.githubCLI]
        }
        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(viewModel.state(for: .githubCLI), .installed(detail: "gh version 2.89.0"))
    }

    func testContinueRefreshesRequiredDependencyAndSavesCompletionOnlyWhenInstalled() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
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
    }

    func testContinueCancelsOptionalInstallAndReturnsItToMissingWhenRequiredRefreshFails() async throws {
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .missing),
            .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
            .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
        ])
        let viewModel = OnboardingViewModel(settingsService: settings, dependencyService: service)

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .installing,
                .codex: .missing(error: nil)
            ],
            activeInstall: .claude
        )
        viewModel.continueOnboarding()

        try await waitUntil("required dependency refresh fails") {
            service.statusRequests == [.githubCLI]
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

@MainActor
private final class OnboardingDependencyServiceFake: OnboardingDependencyService, @unchecked Sendable {
    private var statuses: [OnboardingDependency: OnboardingDependencyStatus]
    private var installs: [OnboardingDependency: Result<OnboardingDependencyStatus, Error>]
    private var suspendedInstalls: Set<OnboardingDependency>
    private var pendingInstallContinuations: [OnboardingDependency: CheckedContinuation<OnboardingDependencyStatus, Error>] = [:]
    private(set) var statusRequests: [OnboardingDependency] = []
    private(set) var installRequests: [OnboardingDependency] = []

    init(
        statuses: [OnboardingDependency: OnboardingDependencyStatus] = [:],
        installs: [OnboardingDependency: Result<OnboardingDependencyStatus, Error>] = [:],
        suspendedInstalls: Set<OnboardingDependency> = []
    ) {
        self.statuses = statuses
        self.installs = installs
        self.suspendedInstalls = suspendedInstalls
    }

    func status(for dependency: OnboardingDependency) async -> OnboardingDependencyStatus {
        statusRequests.append(dependency)
        return statuses[dependency] ?? OnboardingDependencyStatus(dependency: dependency, state: .missing)
    }

    func install(_ dependency: OnboardingDependency) async throws -> OnboardingDependencyStatus {
        installRequests.append(dependency)
        if suspendedInstalls.contains(dependency) {
            return try await withCheckedThrowingContinuation { continuation in
                pendingInstallContinuations[dependency] = continuation
            }
        }
        if let result = installs[dependency] {
            return try result.get()
        }
        let status = statuses[dependency] ?? OnboardingDependencyStatus(dependency: dependency, state: .missing)
        statuses[dependency] = status
        return status
    }

    func completeInstall(
        _ dependency: OnboardingDependency,
        with result: Result<OnboardingDependencyStatus, Error>
    ) {
        guard let continuation = pendingInstallContinuations.removeValue(forKey: dependency) else {
            return
        }
        continuation.resume(with: result)
    }
}

private struct OnboardingViewModelTestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
