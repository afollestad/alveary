import XCTest

@testable import Alveary

final class AppUpdateCheckerTests: XCTestCase {
    func testReportsUpdateWhenLatestVersionIsNewer() async throws {
        let release = try makeRelease(tagName: "v0.1.1")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(release)),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .updateAvailable(release, currentVersion: try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))))
    }

    func testReportsUpToDateForEqualVersion() async throws {
        let release = try makeRelease(tagName: "v0.1.0")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(release)),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .upToDate(release, currentVersion: try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))))
    }

    func testReportsUpToDateForOlderLatestVersion() async throws {
        let release = try makeRelease(tagName: "v0.0.9")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(release)),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .upToDate(release, currentVersion: try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))))
    }

    func testReportsMalformedCurrentVersion() async throws {
        let release = try makeRelease(tagName: "v0.1.1")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(release)),
            versionProvider: StaticAppVersionProvider(versionString: "debug")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .unavailable(.malformedVersion("debug")))
    }

    func testPreservesReleaseLookupFailure() async {
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .unavailable(.privateOrNotFound)),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .unavailable(.privateOrNotFound))
    }
}

private struct StaticAppUpdateReleaseClient: AppUpdateReleaseClient {
    let result: AppUpdateReleaseLookupResult

    func latestRelease() async -> AppUpdateReleaseLookupResult {
        result
    }
}

private struct StaticAppVersionProvider: AppVersionProviding {
    let versionString: String?

    var currentVersionString: String? {
        versionString
    }

    var currentVersion: AppUpdateVersion? {
        versionString.flatMap(AppUpdateVersion.init(string:))
    }
}

private func makeRelease(tagName: String) throws -> AppUpdateRelease {
    AppUpdateRelease(
        tagName: tagName,
        version: try XCTUnwrap(AppUpdateVersion(string: tagName)),
        changelogMarkdown: "Changes",
        htmlURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/tag/\(tagName)")),
        repositoryHTMLURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary")),
        asset: AppUpdateReleaseAsset(
            name: "Alveary.app.zip",
            apiURL: try XCTUnwrap(URL(string: "https://api.github.com/repos/afollestad/alveary/releases/assets/123")),
            downloadURL: try XCTUnwrap(URL(string: "https://github.com/afollestad/alveary/releases/download/\(tagName)/Alveary.app.zip")),
            size: 123
        )
    )
}
