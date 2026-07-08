import Foundation

struct AppUpdateRelease: Equatable, Sendable {
    let tagName: String
    let version: AppUpdateVersion
    let changelogMarkdown: String
    let htmlURL: URL
    let repositoryHTMLURL: URL
    let asset: AppUpdateReleaseAsset
}

struct AppUpdateReleaseAsset: Equatable, Sendable {
    let name: String
    let apiURL: URL
    let downloadURL: URL
    let size: Int?
    let digest: AppUpdateReleaseAssetDigest
}

struct AppUpdateReleaseAssetDigest: Equatable, Sendable {
    let sha256HexDigest: String

    init?(gitHubDigest: String) {
        let components = gitHubDigest
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

        guard components.count == 2,
              components[0].lowercased() == "sha256" else {
            return nil
        }

        self.init(sha256HexDigest: String(components[1]))
    }

    init?(sha256HexDigest: String) {
        let normalizedDigest = sha256HexDigest
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalizedDigest.count == 64,
              normalizedDigest.allSatisfy(\.isHexDigit) else {
            return nil
        }

        self.sha256HexDigest = normalizedDigest
    }

    var gitHubDigest: String {
        "sha256:\(sha256HexDigest)"
    }
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
    case missingAssetDigest(expectedName: String)
    case malformedVersion(String)
    case invalidReleaseURL(String)
    case invalidAssetURL(String)
    case invalidAssetDigest(String)
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
