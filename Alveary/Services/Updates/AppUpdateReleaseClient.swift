import Foundation

protocol AppUpdateReleaseClient: Sendable {
    func latestRelease() async -> AppUpdateReleaseLookupResult
}

struct AppUpdateChecker: Sendable {
    private let releaseClient: any AppUpdateReleaseClient
    private let versionProvider: any AppVersionProviding

    init(
        releaseClient: any AppUpdateReleaseClient,
        versionProvider: any AppVersionProviding
    ) {
        self.releaseClient = releaseClient
        self.versionProvider = versionProvider
    }

    func checkForUpdates() async -> AppUpdateCheckResult {
        guard let currentVersion = versionProvider.currentVersion else {
            return .unavailable(.malformedVersion(versionProvider.currentVersionString ?? ""))
        }

        switch await releaseClient.latestRelease() {
        case .installable(let feed):
            let newerReleaseNotes = feed.releaseNotes
                .filter { $0.version > currentVersion }
                .sorted { $0.version > $1.version }
            let snapshot = AppUpdateCheckSnapshot(
                latestRelease: feed.latestRelease,
                currentVersion: currentVersion,
                releaseNotes: newerReleaseNotes.isEmpty ? [feed.latestRelease.releaseNote] : newerReleaseNotes
            )
            if feed.latestRelease.version > currentVersion {
                return .updateAvailable(snapshot)
            }
            return .upToDate(snapshot)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }
}
