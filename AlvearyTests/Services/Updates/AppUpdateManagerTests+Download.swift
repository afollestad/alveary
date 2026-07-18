import XCTest

@testable import Alveary

@MainActor
extension AppUpdateManagerTests {
    func testDownloadLatestUpdateChecksThenDownloadsAndStagesRelease() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let historicalRelease = try makeManagerTestRelease(tagName: "v0.1.0")
        let downloadedZIPURL = try XCTUnwrap(URL(string: "file:///tmp/Alveary.zip"))
        let stagedUpdate = try makeManagerTestStagedUpdate(release: release)
        let downloader = AppUpdateDownloaderFake(mode: .immediate(downloadedZIPURL))
        let stager = AppUpdateStagerFake(stageResult: stagedUpdate)
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [
                .installable(
                    makeManagerTestFeed(
                        latestRelease: release,
                        releaseNotes: [release.releaseNote, historicalRelease.releaseNote]
                    )
                )
            ]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            downloader: downloader,
            stager: stager
        )

        let result = await manager.downloadLatestUpdate()
        let requestedReleases = await downloader.requestedReleases()
        let stageRequests = await stager.stageRequests()

        XCTAssertEqual(result, stagedUpdate)
        XCTAssertEqual(requestedReleases, [release])
        XCTAssertEqual(stageRequests, [AppUpdateStagerFake.StageRequest(release: release, zipURL: downloadedZIPURL)])
        XCTAssertEqual(manager.downloadState, .readyToInstall(stagedUpdate))
        XCTAssertEqual(manager.stagedUpdate, stagedUpdate)
        XCTAssertEqual(manager.restartPrompt, stagedUpdate)
        XCTAssertEqual(manager.toolbarBadgeState, .readyToInstall)
    }

    func testDownloadLatestUpdateShowsCheckingStateDuringPreflightCheck() async throws {
        let client = AppUpdateReleaseClientFake()
        let manager = AppUpdateManager(
            releaseClient: client,
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            downloader: AppUpdateDownloaderFake(mode: .immediate(try XCTUnwrap(URL(string: "file:///tmp/Alveary.zip")))),
            stager: AppUpdateStagerFake(stageResult: try makeManagerTestStagedUpdate(release: makeManagerTestRelease(tagName: "v0.1.1")))
        )

        let downloadTask = Task { @MainActor in
            await manager.downloadLatestUpdate()
        }
        try await waitUntil("expected preflight update check state") {
            let callCount = await client.callCount()
            return manager.downloadState == .checkingLatestRelease && callCount == 1
        }

        await client.completeNext(with: .unavailable(.noRelease))
        let result = await downloadTask.value

        XCTAssertNil(result)
        XCTAssertEqual(
            manager.downloadState,
            .failed(AppUpdateFailure(message: "No newer Alveary update is available to download."))
        )
    }

    func testCancelDownloadCancelsBackgroundDownloadAndReturnsToIdle() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let downloader = AppUpdateDownloaderFake(mode: .sleepUntilCancelled)
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.installable(makeManagerTestFeed(latestRelease: release))]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            downloader: downloader,
            stager: AppUpdateStagerFake(stageResult: try makeManagerTestStagedUpdate(release: release))
        )

        let downloadTask = Task { @MainActor in
            await manager.downloadLatestUpdate()
        }
        try await waitUntil("expected download to start") {
            if case .downloading = manager.downloadState {
                return true
            }
            return false
        }

        manager.cancelDownload()
        let result = await downloadTask.value
        let requestedReleases = await downloader.requestedReleases()

        XCTAssertNil(result)
        XCTAssertEqual(manager.downloadState, .idle)
        XCTAssertEqual(requestedReleases, [release])
    }

    func testLoadStagedUpdateRestoresReadyToInstallState() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedUpdate = try makeManagerTestStagedUpdate(release: release)
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            stager: AppUpdateStagerFake(loadResult: stagedUpdate)
        )

        await manager.loadStagedUpdateIfAvailable()

        XCTAssertEqual(manager.downloadState, .readyToInstall(stagedUpdate))
        XCTAssertEqual(manager.stagedUpdate, stagedUpdate)
        XCTAssertEqual(manager.restartPrompt, stagedUpdate)
        XCTAssertEqual(manager.toolbarBadgeState, .readyToInstall)
    }

    func testAutomaticChecksTreatMissingStagedUpdateAsIdleAndContinueToReleaseCheck() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.installable(makeManagerTestFeed(latestRelease: release))]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.1"),
            stager: AppUpdateStagerFake()
        )
        defer { manager.stopAutomaticChecks() }

        manager.startAutomaticChecks()
        try await waitUntil("expected automatic check after staged update load") {
            manager.status == .upToDate(
                release,
                currentVersion: AppUpdateVersion(string: "0.1.1")!
            )
        }

        XCTAssertEqual(manager.downloadState, .idle)
        XCTAssertNil(manager.stagedUpdate)
        XCTAssertNil(manager.restartPrompt)
        XCTAssertEqual(manager.toolbarBadgeState, .none)
    }

    func testAutomaticChecksPreserveRealStagedLoadFailure() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let failure = AppUpdateFailure(message: "The staged app signature is invalid.")
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.installable(makeManagerTestFeed(latestRelease: release))]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.1"),
            stager: AppUpdateStagerFake(loadError: failure)
        )
        defer { manager.stopAutomaticChecks() }

        manager.startAutomaticChecks()
        try await waitUntil("expected automatic check after staged load failure") {
            manager.status == .upToDate(
                release,
                currentVersion: AppUpdateVersion(string: "0.1.1")!
            )
        }

        XCTAssertEqual(manager.downloadState, .failed(failure))
        XCTAssertNil(manager.stagedUpdate)
        XCTAssertNil(manager.restartPrompt)
        XCTAssertEqual(manager.toolbarBadgeState, .none)
    }

    func testInstallDownloadedUpdateDelegatesToInstaller() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedUpdate = try makeManagerTestStagedUpdate(release: release)
        let installer = AppUpdateInstallerFake()
        let manager = AppUpdateManager(
            releaseClient: AppUpdateReleaseClientFake(results: [.installable(makeManagerTestFeed(latestRelease: release))]),
            versionProvider: AppUpdateVersionProviderFake(versionString: "0.1.0"),
            downloader: AppUpdateDownloaderFake(mode: .immediate(try XCTUnwrap(URL(string: "file:///tmp/Alveary.zip")))),
            stager: AppUpdateStagerFake(stageResult: stagedUpdate),
            installer: installer
        )
        await manager.downloadLatestUpdate()

        await manager.installDownloadedUpdate()
        let installedUpdates = await installer.installedUpdates()

        XCTAssertEqual(installedUpdates, [stagedUpdate])
        XCTAssertEqual(manager.downloadState, .installing(stagedUpdate))
        XCTAssertNil(manager.restartPrompt)
    }
}

private actor AppUpdateDownloaderFake: AppUpdateDownloading {
    enum Mode: Sendable {
        case immediate(URL)
        case sleepUntilCancelled
    }

    private let mode: Mode
    private var releases: [AppUpdateRelease] = []

    init(mode: Mode) {
        self.mode = mode
    }

    func download(
        release: AppUpdateRelease,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        releases.append(release)
        await progress(0.25)

        switch mode {
        case .immediate(let url):
            await progress(1)
            return url
        case .sleepUntilCancelled:
            try await Task.sleep(for: .seconds(3_600))
            throw CancellationError()
        }
    }

    func requestedReleases() -> [AppUpdateRelease] {
        releases
    }
}

private actor AppUpdateStagerFake: AppUpdateStaging {
    struct StageRequest: Equatable {
        let release: AppUpdateRelease
        let zipURL: URL
    }

    private let stageResult: StagedAppUpdate?
    private let loadResult: StagedAppUpdate?
    private let loadError: AppUpdateFailure?
    private var requests: [StageRequest] = []

    init(
        stageResult: StagedAppUpdate? = nil,
        loadResult: StagedAppUpdate? = nil,
        loadError: AppUpdateFailure? = nil
    ) {
        self.stageResult = stageResult
        self.loadResult = loadResult
        self.loadError = loadError
    }

    func stageDownloadedUpdate(
        release: AppUpdateRelease,
        downloadedZIPURL: URL
    ) async throws -> StagedAppUpdate {
        requests.append(StageRequest(release: release, zipURL: downloadedZIPURL))
        if let stageResult {
            return stageResult
        }
        throw AppUpdateFailure(message: "No staged update configured.")
    }

    func loadValidatedStagedUpdate() async throws -> StagedAppUpdate? {
        if let loadError {
            throw loadError
        }
        return loadResult
    }

    func stageRequests() -> [StageRequest] {
        requests
    }
}

private actor AppUpdateInstallerFake: AppUpdateInstalling {
    private var updates: [StagedAppUpdate] = []

    func installAndRelaunch(stagedUpdate: StagedAppUpdate) async throws {
        updates.append(stagedUpdate)
    }

    func installedUpdates() -> [StagedAppUpdate] {
        updates
    }
}

private func makeManagerTestStagedUpdate(release: AppUpdateRelease) throws -> StagedAppUpdate {
    StagedAppUpdate(
        release: release,
        appBundleURL: try XCTUnwrap(URL(string: "file:///tmp/Alveary.app")),
        metadataURL: try XCTUnwrap(URL(string: "file:///tmp/staged-update.json")),
        stagedAt: Date(timeIntervalSince1970: 200)
    )
}
