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
        case .installable(let release) where release.version > currentVersion:
            return .updateAvailable(release, currentVersion: currentVersion)
        case .installable(let release):
            return .upToDate(release, currentVersion: currentVersion)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }
}
