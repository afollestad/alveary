import Foundation

struct AppUpdateRelease: Equatable, Sendable {
    let tagName: String
    let version: AppUpdateVersion
    let changelogMarkdown: String
    let htmlURL: URL
    let asset: AppUpdateReleaseAsset
}

struct AppUpdateReleaseAsset: Equatable, Sendable {
    let name: String
    let apiURL: URL
    let downloadURL: URL
    let size: Int?
}

enum AppUpdateReleaseLookupResult: Equatable, Sendable {
    case installable(AppUpdateRelease)
    case unavailable(AppUpdateUnavailableReason)
}

enum AppUpdateUnavailableReason: Equatable, Sendable {
    case gitHubCLINotInstalled
    case gitHubCLINotAuthenticated
    case noRelease
    case privateOrNotFound
    case draftRelease
    case prerelease
    case missingAsset(expectedName: String)
    case malformedVersion(String)
    case invalidReleaseURL(String)
    case invalidAssetURL(String)
    case requestFailed(statusCode: Int)
    case rateLimited(resetDate: Date?)
    case decodingFailed(String)
    case transportFailed(String)
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case updateAvailable(AppUpdateRelease, currentVersion: AppUpdateVersion)
    case upToDate(AppUpdateRelease, currentVersion: AppUpdateVersion)
    case unavailable(AppUpdateUnavailableReason)
}
