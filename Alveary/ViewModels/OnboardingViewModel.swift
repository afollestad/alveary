import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    let dependencies = OnboardingDependency.allCases
    var isPresented: Bool
    var dependencyStates: [OnboardingDependency: OnboardingDependencyViewState]
    var activeInstall: OnboardingDependency?
    var isContinuing = false
    var gitHubAuthState: OnboardingGitHubAuthState = .unknown

    @ObservationIgnored private let settingsService: SettingsService
    @ObservationIgnored private let dependencyService: any OnboardingDependencyService
    @ObservationIgnored private let gitHubCLI: (any GitHubCLIService)?
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var continueTask: Task<Void, Never>?
    @ObservationIgnored private var gitHubAuthTask: Task<Void, Never>?

    init(
        settingsService: SettingsService,
        dependencyService: any OnboardingDependencyService,
        gitHubCLI: (any GitHubCLIService)? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.settingsService = settingsService
        self.dependencyService = dependencyService
        self.gitHubCLI = gitHubCLI
        self.openURL = openURL
        self.isPresented = !settingsService.current.hasCompletedOnboarding
        self.dependencyStates = Dictionary(
            uniqueKeysWithValues: OnboardingDependency.allCases.map { dependency in
                (dependency, OnboardingDependencyViewState.checking)
            }
        )
    }

    deinit {
        refreshTask?.cancel()
        installTask?.cancel()
        continueTask?.cancel()
        gitHubAuthTask?.cancel()
    }

    var canContinue: Bool {
        guard !isContinuing else {
            return false
        }
        return OnboardingDependency.requiredCases.allSatisfy { state(for: $0).isInstalled }
    }

    func start() {
        guard !didStart else {
            return
        }
        didStart = true

        if settingsService.current.hasCompletedOnboarding {
            isPresented = false
            refreshRequiredStatusForCompletedOnboarding()
        } else {
            isPresented = true
            refreshVisibleStatuses()
        }
    }

    func handleAppDidBecomeActive() {
        if settingsService.current.hasCompletedOnboarding, !isPresented {
            refreshRequiredStatusForCompletedOnboarding()
        } else {
            isPresented = true
            refreshVisibleStatuses()
        }
    }

    func state(for dependency: OnboardingDependency) -> OnboardingDependencyViewState {
        dependencyStates[dependency] ?? .checking
    }

    func canInstall(_ dependency: OnboardingDependency) -> Bool {
        guard activeInstall == nil else {
            return false
        }
        switch state(for: dependency) {
        case .missing:
            return true
        case .checking, .installing, .installed:
            return false
        }
    }

    func install(_ dependency: OnboardingDependency) {
        guard canInstall(dependency) else {
            return
        }

        refreshTask?.cancel()
        installTask?.cancel()
        installTask = Task { @MainActor in
            activeInstall = dependency
            dependencyStates[dependency] = .installing
            do {
                let status = try await dependencyService.install(dependency)
                guard !Task.isCancelled else {
                    return
                }
                apply(status)
            } catch is CancellationError {
                guard !Task.isCancelled else {
                    return
                }
                dependencyStates[dependency] = .missing(error: nil)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                dependencyStates[dependency] = .missing(error: error.localizedDescription)
            }

            if activeInstall == dependency {
                activeInstall = nil
            }
        }
    }

    func continueOnboarding() {
        guard canContinue else {
            return
        }

        cancelOptionalInstall()
        continueTask?.cancel()
        continueTask = Task { @MainActor in
            isContinuing = true
            defer { isContinuing = false }

            var allRequiredInstalled = true
            for dependency in OnboardingDependency.requiredCases {
                let requiredStatus = await dependencyService.status(for: dependency)
                guard !Task.isCancelled else {
                    return
                }
                apply(requiredStatus)
                allRequiredInstalled = allRequiredInstalled && requiredStatus.isInstalled
            }

            guard allRequiredInstalled else {
                isPresented = true
                return
            }

            settingsService.update {
                $0.hasCompletedOnboarding = true
            }
            isPresented = false
        }
    }

    func cancelInstallersForDismissal() {
        installTask?.cancel()
        installTask = nil
        activeInstall = nil
        cancelGitHubAuthentication()
    }

    /// Authentication is offered after `gh` installs but never gates Continue: requiring a GitHub
    /// account and a network round trip at first launch would block work the app can do locally.
    var showsGitHubConnect: Bool {
        guard gitHubCLI != nil, state(for: .githubCLI).isInstalled else {
            return false
        }
        switch gitHubAuthState {
        case .connected, .unknown:
            return false
        case .checking, .notConnected, .connecting, .failed:
            return true
        }
    }

    func connectGitHub() {
        guard let gitHubCLI, !gitHubAuthState.isConnecting else {
            return
        }

        gitHubAuthTask?.cancel()
        gitHubAuthTask = Task { @MainActor in
            gitHubAuthState = .connecting(deviceCode: nil)
            do {
                let deviceCode = try await gitHubCLI.authenticate()
                guard !Task.isCancelled else {
                    return
                }
                gitHubAuthState = .connecting(deviceCode: deviceCode)
                // `gh auth login --web` cannot open a browser without a TTY, so do it here.
                openURL(deviceCode.verificationURL)

                let didAuthenticate = try await gitHubCLI.awaitAuthentication()
                guard !Task.isCancelled else {
                    return
                }
                gitHubAuthState = didAuthenticate
                    ? .connected
                    : .failed(message: "GitHub authentication did not complete.")
            } catch is CancellationError {
                // A cancelled task's owner already chose the follow-up state; writing here would
                // stomp a newer interaction's `.connecting`.
                guard !Task.isCancelled else {
                    return
                }
                gitHubAuthState = .notConnected
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                gitHubAuthState = .failed(message: error.localizedDescription)
            }
        }
    }

    func openGitHubVerificationURL() {
        guard case .connecting(let deviceCode) = gitHubAuthState,
              let deviceCode else {
            return
        }
        openURL(deviceCode.verificationURL)
    }

    private func cancelGitHubAuthentication() {
        guard gitHubAuthState.isConnecting else {
            return
        }
        gitHubAuthTask?.cancel()
        gitHubAuthTask = nil
        gitHubCLI?.cancelAuthentication()
        gitHubAuthState = .notConnected
    }

    private func refreshGitHubAuthStateIfNeeded() {
        guard let gitHubCLI, gitHubAuthState == .unknown else {
            return
        }

        gitHubAuthState = .checking
        gitHubAuthTask?.cancel()
        gitHubAuthTask = Task { @MainActor in
            let isAuthenticated = await gitHubCLI.isAuthenticated()
            guard !Task.isCancelled, gitHubAuthState == .checking else {
                return
            }
            gitHubAuthState = isAuthenticated ? .connected : .notConnected
        }
    }

    func setPresentationForTesting(
        isPresented: Bool,
        states: [OnboardingDependency: OnboardingDependencyViewState],
        activeInstall: OnboardingDependency? = nil,
        isContinuing: Bool = false
    ) {
        self.isPresented = isPresented
        self.dependencyStates = states
        self.activeInstall = activeInstall
        self.isContinuing = isContinuing
    }

    private func refreshVisibleStatuses() {
        scheduleRefresh(.visible)
    }

    private func refreshRequiredStatusForCompletedOnboarding() {
        scheduleRefresh(.completedRequiredOnly)
    }

    private func scheduleRefresh(_ mode: OnboardingRefreshMode) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            await performRefresh(mode)
        }
    }

    private func performRefresh(_ mode: OnboardingRefreshMode) async {
        let dependenciesToRefresh = mode.dependencies
        for dependency in dependenciesToRefresh where dependency != activeInstall {
            dependencyStates[dependency] = .checking
        }

        for dependency in dependenciesToRefresh {
            guard !Task.isCancelled else {
                return
            }
            guard dependency != activeInstall else {
                continue
            }
            let status = await dependencyService.status(for: dependency)
            guard !Task.isCancelled else {
                return
            }
            apply(status)
        }

        guard mode == .completedRequiredOnly,
              settingsService.current.hasCompletedOnboarding else {
            return
        }

        if OnboardingDependency.requiredCases.allSatisfy({ state(for: $0).isInstalled }) {
            isPresented = false
        } else {
            isPresented = true
            await refreshOptionalStatusesIfVisible()
        }
    }

    private func refreshOptionalStatusesIfVisible() async {
        guard isPresented else {
            return
        }
        for dependency in OnboardingDependency.allCases where !dependency.required && dependency != activeInstall {
            dependencyStates[dependency] = .checking
        }
        for dependency in OnboardingDependency.allCases where !dependency.required {
            guard !Task.isCancelled else {
                return
            }
            guard dependency != activeInstall else {
                continue
            }
            let status = await dependencyService.status(for: dependency)
            guard !Task.isCancelled else {
                return
            }
            apply(status)
        }
    }

    private func apply(_ status: OnboardingDependencyStatus) {
        switch status.state {
        case .installed(let detail):
            dependencyStates[status.dependency] = .installed(detail: detail)
        case .missing:
            dependencyStates[status.dependency] = .missing(error: nil)
        }

        guard status.dependency == .githubCLI else {
            return
        }
        if status.isInstalled {
            refreshGitHubAuthStateIfNeeded()
        } else {
            // A vanished CLI also strands any in-flight device login; end it with the row.
            cancelGitHubAuthentication()
            gitHubAuthState = .unknown
        }
    }

    private func cancelOptionalInstall() {
        guard let activeInstall,
              !activeInstall.required else {
            return
        }
        installTask?.cancel()
        installTask = nil
        dependencyStates[activeInstall] = .missing(error: nil)
        self.activeInstall = nil
    }
}

enum OnboardingGitHubAuthState: Sendable, Equatable {
    case unknown
    case checking
    case notConnected
    case connecting(deviceCode: GitHubDeviceCode?)
    case connected
    case failed(message: String)

    var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }
}

enum OnboardingDependencyViewState: Sendable, Equatable {
    case checking
    case missing(error: String?)
    case installing
    case installed(detail: String?)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isFailed: Bool {
        if case .missing(let error) = self,
           error != nil {
            return true
        }
        return false
    }

    var detail: String? {
        switch self {
        case .installed(let detail):
            return detail
        case .missing(let error):
            return error
        case .checking, .installing:
            return nil
        }
    }
}

private enum OnboardingRefreshMode: Equatable {
    case visible
    case completedRequiredOnly

    var dependencies: [OnboardingDependency] {
        switch self {
        case .visible:
            return OnboardingDependency.allCases
        case .completedRequiredOnly:
            return OnboardingDependency.requiredCases
        }
    }
}
