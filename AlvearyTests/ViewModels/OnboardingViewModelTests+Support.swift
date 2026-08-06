import Foundation

@testable import Alveary

@MainActor
final class OnboardingDependencyServiceFake: OnboardingDependencyService, @unchecked Sendable {
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

struct OnboardingViewModelTestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
