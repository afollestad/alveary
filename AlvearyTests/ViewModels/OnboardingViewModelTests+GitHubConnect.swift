import Foundation
import XCTest

@testable import Alveary

@MainActor
extension OnboardingViewModelTests {
    func testGitHubAuthStateRefreshesOnceTheCLIIsDetected() async throws {
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: false)
        let viewModel = makeConnectViewModel(gitHubCLI: gitHubCLI, gitHubCLIInstalled: true)

        viewModel.start()

        try await waitUntil("GitHub auth state resolves after the CLI is detected") {
            viewModel.gitHubAuthState == .notConnected
        }
        XCTAssertTrue(viewModel.showsGitHubConnect)
    }

    func testGitHubConnectSectionStaysHiddenWhenAlreadyAuthenticated() async throws {
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: true)
        let viewModel = makeConnectViewModel(gitHubCLI: gitHubCLI, gitHubCLIInstalled: true)

        viewModel.start()

        try await waitUntil("GitHub auth state resolves as connected") {
            viewModel.gitHubAuthState == .connected
        }
        XCTAssertFalse(viewModel.showsGitHubConnect)
    }

    func testGitHubConnectSectionStaysHiddenWhileTheCLIIsMissing() async throws {
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: false)
        let viewModel = makeConnectViewModel(gitHubCLI: gitHubCLI, gitHubCLIInstalled: false)

        viewModel.start()

        try await waitUntil("required statuses refresh") {
            viewModel.state(for: .githubCLI) == .missing(error: nil)
        }
        XCTAssertFalse(viewModel.showsGitHubConnect)
        XCTAssertEqual(viewModel.gitHubAuthState, .unknown)
    }

    func testConnectPublishesDeviceCodeOpensBrowserAndReportsSuccess() async throws {
        let deviceCode = GitHubDeviceCode(
            code: "ABCD-1234",
            verificationURL: try XCTUnwrap(URL(string: "https://github.com/login/device"))
        )
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: false, deviceCode: deviceCode)
        let openedURLs = OpenedURLRecorder()
        let viewModel = makeConnectViewModel(
            gitHubCLI: gitHubCLI,
            gitHubCLIInstalled: true,
            openURL: { openedURLs.append($0) }
        )

        viewModel.connectGitHub()

        try await waitUntil("device code publishes and the browser opens") {
            viewModel.gitHubAuthState == .connecting(deviceCode: deviceCode)
                && openedURLs.urls == [deviceCode.verificationURL]
        }

        // `gh auth login --web` cannot open a browser without a TTY, so the app must do it.
        gitHubCLI.completeAuthentication(with: true)
        try await waitUntil("authentication completes") {
            viewModel.gitHubAuthState == .connected
        }
        XCTAssertFalse(viewModel.showsGitHubConnect)
    }

    func testConnectFailureSurfacesMessageAndKeepsSectionVisible() async throws {
        let gitHubCLI = OnboardingConnectGitHubCLIFake(
            isAuthenticated: false,
            authenticateError: GitHubError.authLaunchFailed("gh is unavailable")
        )
        let viewModel = makeConnectViewModel(gitHubCLI: gitHubCLI, gitHubCLIInstalled: true)
        seedInstalledGitHubCLI(on: viewModel)

        viewModel.connectGitHub()

        try await waitUntil("connect failure surfaces") {
            if case .failed = viewModel.gitHubAuthState {
                return true
            }
            return false
        }
        XCTAssertTrue(viewModel.showsGitHubConnect)
    }

    func testDismissalCancelsInFlightAuthentication() async throws {
        let deviceCode = GitHubDeviceCode(
            code: "ABCD-1234",
            verificationURL: try XCTUnwrap(URL(string: "https://github.com/login/device"))
        )
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: false, deviceCode: deviceCode)
        let viewModel = makeConnectViewModel(gitHubCLI: gitHubCLI, gitHubCLIInstalled: true)

        viewModel.connectGitHub()
        try await waitUntil("authentication is in flight") {
            viewModel.gitHubAuthState.isConnecting
        }

        viewModel.cancelInstallersForDismissal()

        XCTAssertEqual(viewModel.gitHubAuthState, .notConnected)
        XCTAssertTrue(gitHubCLI.didCancelAuthentication)
    }

    func testContinueDoesNotWaitOnGitHubAuthentication() async throws {
        let gitHubCLI = OnboardingConnectGitHubCLIFake(isAuthenticated: false)
        let settings = InMemorySettingsService()
        let service = OnboardingDependencyServiceFake(statuses: [
            .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
            .githubCLI: OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0"))
        ])
        let viewModel = OnboardingViewModel(
            settingsService: settings,
            dependencyService: service,
            gitHubCLI: gitHubCLI,
            openURL: { _ in }
        )

        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )
        XCTAssertTrue(viewModel.canContinue)
        viewModel.continueOnboarding()

        try await waitUntil("onboarding completes without being signed in") {
            settings.current.hasCompletedOnboarding
        }
    }

    /// `showsGitHubConnect` is gated on the detected `gh` row, so tests that skip `start()`
    /// have to seed it themselves.
    private func seedInstalledGitHubCLI(on viewModel: OnboardingViewModel) {
        viewModel.setPresentationForTesting(
            isPresented: true,
            states: [
                .commandLineTools: .installed(detail: "git version 2.51.0"),
                .githubCLI: .installed(detail: "gh version 2.89.0"),
                .claude: .missing(error: nil),
                .codex: .missing(error: nil)
            ]
        )
    }

    private func makeConnectViewModel(
        gitHubCLI: OnboardingConnectGitHubCLIFake,
        gitHubCLIInstalled: Bool,
        openURL: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> OnboardingViewModel {
        let gitHubStatus = OnboardingDependencyStatus(
            dependency: .githubCLI,
            state: gitHubCLIInstalled ? .installed(detail: "gh version 2.89.0") : .missing
        )
        return OnboardingViewModel(
            settingsService: InMemorySettingsService(),
            dependencyService: OnboardingDependencyServiceFake(statuses: [
                .commandLineTools: OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0")),
                .githubCLI: gitHubStatus,
                .claude: OnboardingDependencyStatus(dependency: .claude, state: .missing),
                .codex: OnboardingDependencyStatus(dependency: .codex, state: .missing)
            ]),
            gitHubCLI: gitHubCLI,
            openURL: openURL
        )
    }
}

@MainActor
private final class OpenedURLRecorder {
    private(set) var urls: [URL] = []

    func append(_ url: URL) {
        urls.append(url)
    }
}

@MainActor
final class OnboardingConnectGitHubCLIFake: GitHubCLIService, @unchecked Sendable {
    private let isAuthenticatedResult: Bool
    private let deviceCode: GitHubDeviceCode?
    private let authenticateError: (any Error)?
    private var authenticationContinuation: CheckedContinuation<Bool, Error>?
    private(set) var didCancelAuthentication = false

    init(
        isAuthenticated: Bool,
        deviceCode: GitHubDeviceCode? = nil,
        authenticateError: (any Error)? = nil
    ) {
        self.isAuthenticatedResult = isAuthenticated
        self.deviceCode = deviceCode
        self.authenticateError = authenticateError
    }

    func checkInstalled() async -> String? {
        "gh version 2.89.0"
    }

    func isAuthenticated() async -> Bool {
        isAuthenticatedResult
    }

    func authenticate() async throws -> GitHubDeviceCode {
        if let authenticateError {
            throw authenticateError
        }
        guard let deviceCode else {
            throw GitHubError.authParseFailed
        }
        return deviceCode
    }

    func awaitAuthentication() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            authenticationContinuation = continuation
        }
    }

    func cancelAuthentication() {
        didCancelAuthentication = true
        authenticationContinuation?.resume(throwing: CancellationError())
        authenticationContinuation = nil
    }

    func completeAuthentication(with result: Bool) {
        authenticationContinuation?.resume(returning: result)
        authenticationContinuation = nil
    }
}
