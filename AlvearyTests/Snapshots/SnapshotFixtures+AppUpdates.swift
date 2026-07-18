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

    func snapshotDownloadingAppUpdateManager(feed: AppUpdateReleaseFeed) -> AppUpdateManager {
        snapshotAppUpdateManager(
            result: .installable(feed),
            downloader: SnapshotPendingAppUpdateDownloader(progress: 0.42),
            stager: SnapshotAppUpdateStager()
        )
    }

    func snapshotFailedDownloadAppUpdateManager(feed: AppUpdateReleaseFeed) -> AppUpdateManager {
        snapshotAppUpdateManager(
            result: .installable(feed),
            downloader: SnapshotFailingAppUpdateDownloader(),
            stager: SnapshotAppUpdateStager()
        )
    }

    func snapshotAppUpdateFeed() throws -> AppUpdateReleaseFeed {
        let latestRelease = try snapshotAppUpdateRelease()
        return AppUpdateReleaseFeed(
            latestRelease: latestRelease,
            releaseNotes: [
                latestRelease.releaseNote,
                AppUpdateReleaseNote(
                    tagName: "v0.1.2",
                    version: try XCTUnwrap(AppUpdateVersion(string: "v0.1.2")),
                    changelogMarkdown: ""
                ),
                AppUpdateReleaseNote(
                    tagName: "v0.1.1",
                    version: try XCTUnwrap(AppUpdateVersion(string: "v0.1.1")),
                    changelogMarkdown: "- Added authenticated GitHub release checks."
                )
            ]
        )
    }

    private func snapshotAppUpdateRelease() throws -> AppUpdateRelease {
        let tagName = "v0.1.3"
        let downloadURL = "https://github.com/afollestad/alveary/releases/download/\(tagName)/Alveary.app.zip"
        return AppUpdateRelease(
            tagName: tagName,
            version: try XCTUnwrap(AppUpdateVersion(string: tagName)),
            changelogMarkdown: """
            - Combined release notes for every newer version.
            - Kept [repository-relative links](/afollestad/alveary/releases) interactive.
            """,
            htmlURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/tag/\(tagName)")),
            repositoryHTMLURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary")),
            asset: AppUpdateReleaseAsset(
                name: "Alveary.app.zip",
                apiURL: try XCTUnwrap(URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123")),
                downloadURL: try XCTUnwrap(URL(string: downloadURL)),
                size: 12_345_678,
                digest: try XCTUnwrap(AppUpdateReleaseAssetDigest(sha256HexDigest: String(repeating: "a", count: 64)))
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
