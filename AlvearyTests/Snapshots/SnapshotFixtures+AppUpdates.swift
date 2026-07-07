import XCTest

@testable import Alveary

extension SnapshotTests {
    func snapshotAppUpdateManager(
        result: AppUpdateReleaseLookupResult = .unavailable(.privateOrNotFound),
        versionString: String = "0.1.0",
        downloader: (any AppUpdateDownloading)? = nil,
        stager: (any AppUpdateStaging)? = nil
    ) -> AppUpdateManager {
        AppUpdateManager(
            releaseClient: SnapshotAppUpdateReleaseClient(result: result),
            versionProvider: SnapshotAppVersionProvider(versionString: versionString),
            downloader: downloader,
            stager: stager,
            scheduleTiming: AppUpdateScheduleTiming(
                automaticCheckInterval: .seconds(21_600),
                now: { Date(timeIntervalSince1970: 1_783_468_800) },
                sleep: { _ in throw CancellationError() }
            )
        )
    }

    func snapshotDownloadingAppUpdateManager(release: AppUpdateRelease) -> AppUpdateManager {
        snapshotAppUpdateManager(
            result: .installable(release),
            downloader: SnapshotPendingAppUpdateDownloader(progress: 0.42),
            stager: SnapshotAppUpdateStager()
        )
    }

    func snapshotFailedDownloadAppUpdateManager(release: AppUpdateRelease) -> AppUpdateManager {
        snapshotAppUpdateManager(
            result: .installable(release),
            downloader: SnapshotFailingAppUpdateDownloader(),
            stager: SnapshotAppUpdateStager()
        )
    }

    func snapshotAppUpdateRelease() throws -> AppUpdateRelease {
        let downloadURL = "https://github.com/afollestad/alveary/releases/download/v0.1.1/Alveary.app.zip"
        return AppUpdateRelease(
            tagName: "v0.1.1",
            version: try XCTUnwrap(AppUpdateVersion(string: "v0.1.1")),
            changelogMarkdown: """
            ## Changes

            - Added **GitHub Releases** update checks.
            - Rendered release notes with shared markdown.
            - See [full release notes](/afollestad/alveary/releases/tag/v0.1.1).
            """,
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/tag/v0.1.1")),
            repositoryHTMLURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary")),
            asset: AppUpdateReleaseAsset(
                name: "Alveary.app.zip",
                apiURL: try XCTUnwrap(URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123")),
                downloadURL: try XCTUnwrap(URL(string: downloadURL)),
                size: 12_345_678
            )
        )
    }
}

private actor SnapshotAppUpdateReleaseClient: AppUpdateReleaseClient {
    private let result: AppUpdateReleaseLookupResult

    init(result: AppUpdateReleaseLookupResult) {
        self.result = result
    }

    func latestRelease() async -> AppUpdateReleaseLookupResult {
        result
    }
}

private struct SnapshotAppVersionProvider: AppVersionProviding {
    let versionString: String?

    var currentVersionString: String? {
        versionString
    }

    var currentVersion: AppUpdateVersion? {
        versionString.flatMap(AppUpdateVersion.init(string:))
    }
}

private actor SnapshotPendingAppUpdateDownloader: AppUpdateDownloading {
    private let progressValue: Double

    init(progress: Double) {
        progressValue = progress
    }

    func download(
        release: AppUpdateRelease,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        await progress(progressValue)
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
    }
}

private actor SnapshotFailingAppUpdateDownloader: AppUpdateDownloading {
    func download(
        release: AppUpdateRelease,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        await progress(0.38)
        throw AppUpdateFailure(message: "Network connection was lost while downloading Alveary.")
    }
}

private struct SnapshotAppUpdateStager: AppUpdateStaging {
    func stageDownloadedUpdate(
        release: AppUpdateRelease,
        downloadedZIPURL: URL
    ) async throws -> StagedAppUpdate {
        throw AppUpdateFailure(message: "Snapshot downloads should not finish staging.")
    }

    func loadValidatedStagedUpdate() async throws -> StagedAppUpdate? {
        nil
    }
}
