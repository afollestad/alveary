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

    @ObservationIgnored private let settingsService: SettingsService
    @ObservationIgnored private let dependencyService: any OnboardingDependencyService
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var continueTask: Task<Void, Never>?

    init(
        settingsService: SettingsService,
        dependencyService: any OnboardingDependencyService
    ) {
        self.settingsService = settingsService
        self.dependencyService = dependencyService
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
    }

    var canContinue: Bool {
        guard !isContinuing else {
            return false
        }
        return state(for: .githubCLI).isInstalled
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

            let requiredStatus = await dependencyService.status(for: .githubCLI)
            guard !Task.isCancelled else {
                return
            }

            apply(requiredStatus)
            guard requiredStatus.isInstalled else {
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

        if state(for: .githubCLI).isInstalled {
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
            return [.githubCLI]
        }
    }
}
