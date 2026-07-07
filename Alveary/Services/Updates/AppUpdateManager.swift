import Foundation
import Observation

private let appUpdateAutomaticCheckInterval: Duration = .seconds(21_600)

enum AppUpdateCheckTrigger: Equatable, Sendable {
    case automatic
    case manual
}

enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case updateAvailable(AppUpdateRelease, currentVersion: AppUpdateVersion)
    case upToDate(AppUpdateRelease, currentVersion: AppUpdateVersion)
    case unavailable(AppUpdateUnavailableReason)
}

struct AppUpdateScheduleTiming: Sendable {
    static let live = AppUpdateScheduleTiming(
        automaticCheckInterval: appUpdateAutomaticCheckInterval,
        now: { Date() },
        sleep: { duration in
            try await Task.sleep(for: duration)
        }
    )

    let automaticCheckInterval: Duration
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
}

@MainActor
@Observable
final class AppUpdateManager {
    @ObservationIgnored private let versionProvider: any AppVersionProviding
    private let checker: AppUpdateChecker
    private let scheduleTiming: AppUpdateScheduleTiming
    private var didStartAutomaticChecks = false
    private var automaticScheduleTask: Task<Void, Never>?
    private var activeCheckTask: Task<AppUpdateCheckResult, Never>?
    private var activeCheckID: UUID?

    private(set) var status: AppUpdateStatus = .idle
    private(set) var isChecking = false
    private(set) var latestRelease: AppUpdateRelease?
    private(set) var currentVersion: AppUpdateVersion?
    private(set) var lastCheckedAt: Date?
    private(set) var lastManualFailure: AppUpdateUnavailableReason?

    init(
        releaseClient: any AppUpdateReleaseClient,
        versionProvider: any AppVersionProviding,
        scheduleTiming: AppUpdateScheduleTiming = .live
    ) {
        self.versionProvider = versionProvider
        checker = AppUpdateChecker(
            releaseClient: releaseClient,
            versionProvider: versionProvider
        )
        self.scheduleTiming = scheduleTiming
        currentVersion = versionProvider.currentVersion
    }

    func startAutomaticChecks() {
        guard !didStartAutomaticChecks else {
            return
        }

        didStartAutomaticChecks = true
        Task { [weak self] in
            await self?.runCheck(trigger: .automatic)
        }
    }

    @discardableResult
    func forceCheck() async -> AppUpdateCheckResult {
        await runCheck(trigger: .manual)
    }

    var currentVersionString: String? {
        versionProvider.currentVersionString
    }

    func stopAutomaticChecks() {
        didStartAutomaticChecks = false
        automaticScheduleTask?.cancel()
        automaticScheduleTask = nil
    }

    @discardableResult
    func runCheck(trigger: AppUpdateCheckTrigger) async -> AppUpdateCheckResult {
        let check = currentOrStartedCheck()
        let result = await check.task.value

        if activeCheckID == check.id {
            activeCheckTask = nil
            activeCheckID = nil
            isChecking = false
            lastCheckedAt = scheduleTiming.now()
        }

        apply(result, trigger: trigger)
        scheduleNextAutomaticCheckIfNeeded()
        return result
    }

}

private extension AppUpdateManager {
    func currentOrStartedCheck() -> (id: UUID, task: Task<AppUpdateCheckResult, Never>) {
        if let activeCheckTask, let activeCheckID {
            return (activeCheckID, activeCheckTask)
        }

        let checkID = UUID()
        let checker = checker
        let task = Task.detached(priority: .utility) {
            await checker.checkForUpdates()
        }
        activeCheckID = checkID
        activeCheckTask = task
        isChecking = true
        return (checkID, task)
    }

    func apply(_ result: AppUpdateCheckResult, trigger: AppUpdateCheckTrigger) {
        switch result {
        case .updateAvailable(let release, let currentVersion):
            latestRelease = release
            self.currentVersion = currentVersion
            lastManualFailure = nil
            status = .updateAvailable(release, currentVersion: currentVersion)
        case .upToDate(let release, let currentVersion):
            latestRelease = release
            self.currentVersion = currentVersion
            lastManualFailure = nil
            status = .upToDate(release, currentVersion: currentVersion)
        case .unavailable(let reason):
            guard trigger == .manual else {
                return
            }
            lastManualFailure = reason
            status = .unavailable(reason)
        }
    }

    func scheduleNextAutomaticCheckIfNeeded() {
        guard didStartAutomaticChecks else {
            return
        }

        automaticScheduleTask?.cancel()
        let scheduleTiming = scheduleTiming
        automaticScheduleTask = Task { [weak self] in
            do {
                try await scheduleTiming.sleep(scheduleTiming.automaticCheckInterval)
            } catch {
                return
            }
            await self?.runCheck(trigger: .automatic)
        }
    }
}
