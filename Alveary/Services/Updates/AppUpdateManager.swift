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
    private let downloader: (any AppUpdateDownloading)?
    private let stager: (any AppUpdateStaging)?
    private let installer: (any AppUpdateInstalling)?
    private let checker: AppUpdateChecker
    private let scheduleTiming: AppUpdateScheduleTiming
    private var didStartAutomaticChecks = false
    private var automaticScheduleTask: Task<Void, Never>?
    private var activeCheckTask: Task<AppUpdateCheckResult, Never>?
    private var activeCheckID: UUID?
    private var activeDownloadTask: Task<StagedAppUpdate, any Error>?
    private var activeDownloadID: UUID?

    private(set) var status: AppUpdateStatus = .idle
    private(set) var isChecking = false
    private(set) var latestRelease: AppUpdateRelease?
    private(set) var releaseNotes: [AppUpdateReleaseNote] = []
    private(set) var currentVersion: AppUpdateVersion?
    private(set) var lastCheckedAt: Date?
    private(set) var lastManualFailure: AppUpdateUnavailableReason?
    private(set) var downloadState: AppUpdateDownloadState = .idle
    private(set) var stagedUpdate: StagedAppUpdate?
    var restartPrompt: StagedAppUpdate?

    init(
        releaseClient: any AppUpdateReleaseClient,
        versionProvider: any AppVersionProviding,
        downloader: (any AppUpdateDownloading)? = nil,
        stager: (any AppUpdateStaging)? = nil,
        installer: (any AppUpdateInstalling)? = nil,
        scheduleTiming: AppUpdateScheduleTiming = .live
    ) {
        self.versionProvider = versionProvider
        self.downloader = downloader
        self.stager = stager
        self.installer = installer
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
            await self?.loadStagedUpdateIfAvailable()
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

    func dismissRestartPrompt() {
        restartPrompt = nil
    }

    func promptForRestartIfUpdateIsReady() {
        guard let stagedUpdate else {
            return
        }
        restartPrompt = stagedUpdate
    }

    func loadStagedUpdateIfAvailable() async {
        guard stagedUpdate == nil,
              let stager else {
            return
        }

        do {
            guard let loadedUpdate = try await stager.loadValidatedStagedUpdate() else {
                return
            }
            stagedUpdate = loadedUpdate
            downloadState = .readyToInstall(loadedUpdate)
            restartPrompt = loadedUpdate
        } catch {
            downloadState = .failed(.from(error))
        }
    }

    @discardableResult
    func downloadLatestUpdate() async -> StagedAppUpdate? {
        if let activeDownloadTask {
            return try? await activeDownloadTask.value
        }

        downloadState = .checkingLatestRelease
        let checkResult = await forceCheck()
        guard case .updateAvailable(let snapshot) = checkResult else {
            downloadState = .failed(AppUpdateFailure(message: "No newer Alveary update is available to download."))
            return nil
        }
        guard let downloader,
              let stager else {
            downloadState = .failed(AppUpdateFailure(message: "This Alveary build cannot download updates."))
            return nil
        }

        let release = snapshot.latestRelease
        downloadState = .downloading(release, progress: 0)
        let download = startDownloadTask(
            release: release,
            downloader: downloader,
            stager: stager
        )
        activeDownloadTask = download.task
        activeDownloadID = download.id

        do {
            return try await finishDownloadTask(download)
        } catch is CancellationError {
            clearActiveDownload(id: download.id, state: .idle)
            return nil
        } catch {
            clearActiveDownload(id: download.id, state: .failed(.from(error)))
            return nil
        }
    }

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadID = nil
        downloadState = .idle
    }

    func installDownloadedUpdate() async {
        guard let stagedUpdate else {
            downloadState = .failed(AppUpdateFailure(message: "No downloaded update is ready to install."))
            return
        }
        guard let installer else {
            downloadState = .failed(AppUpdateFailure(message: "This Alveary build cannot install updates."))
            return
        }

        downloadState = .installing(stagedUpdate)
        restartPrompt = nil
        do {
            try await installer.installAndRelaunch(stagedUpdate: stagedUpdate)
        } catch {
            downloadState = .failed(.from(error))
        }
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
    func startDownloadTask(
        release: AppUpdateRelease,
        downloader: any AppUpdateDownloading,
        stager: any AppUpdateStaging
    ) -> (id: UUID, task: Task<StagedAppUpdate, any Error>) {
        let downloadID = UUID()
        let task = Task.detached(priority: .utility) { [weak self, downloader, stager] in
            let downloadedZIPURL = try await downloader.download(release: release) { progress in
                await MainActor.run {
                    guard self?.activeDownloadID == downloadID else {
                        return
                    }
                    self?.downloadState = .downloading(release, progress: progress)
                }
            }
            try Task.checkCancellation()
            await MainActor.run {
                guard self?.activeDownloadID == downloadID else {
                    return
                }
                self?.downloadState = .staging(release)
            }
            try Task.checkCancellation()
            return try await stager.stageDownloadedUpdate(
                release: release,
                downloadedZIPURL: downloadedZIPURL
            )
        }
        return (downloadID, task)
    }

    func finishDownloadTask(_ download: (id: UUID, task: Task<StagedAppUpdate, any Error>)) async throws -> StagedAppUpdate? {
        let stagedUpdate = try await download.task.value
        guard activeDownloadID == download.id else {
            return stagedUpdate
        }
        activeDownloadTask = nil
        activeDownloadID = nil
        self.stagedUpdate = stagedUpdate
        downloadState = .readyToInstall(stagedUpdate)
        restartPrompt = stagedUpdate
        return stagedUpdate
    }

    func clearActiveDownload(id: UUID, state: AppUpdateDownloadState) {
        guard activeDownloadID == id else {
            return
        }
        activeDownloadTask = nil
        activeDownloadID = nil
        downloadState = state
    }

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
        case .updateAvailable(let snapshot):
            latestRelease = snapshot.latestRelease
            releaseNotes = snapshot.releaseNotes
            currentVersion = snapshot.currentVersion
            lastManualFailure = nil
            status = .updateAvailable(snapshot.latestRelease, currentVersion: snapshot.currentVersion)
        case .upToDate(let snapshot):
            latestRelease = snapshot.latestRelease
            releaseNotes = snapshot.releaseNotes
            currentVersion = snapshot.currentVersion
            lastManualFailure = nil
            status = .upToDate(snapshot.latestRelease, currentVersion: snapshot.currentVersion)
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
