import XCTest

@testable import Alveary

final class AppUpdateCheckerTests: XCTestCase {
    func testReportsUpdateWhenLatestVersionIsNewer() async throws {
        let release = try makeRelease(tagName: "v0.1.1")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(makeFeed(latestRelease: release))),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        let currentVersion = try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))
        XCTAssertEqual(
            result,
            .updateAvailable(
                AppUpdateCheckSnapshot(
                    latestRelease: release,
                    currentVersion: currentVersion,
                    releaseNotes: [release.releaseNote]
                )
            )
        )
    }

    func testIncludesEveryNewerReleaseNoteInDescendingVersionOrder() async throws {
        let latestRelease = try makeRelease(tagName: "v0.1.5")
        let notes = try ["v0.1.2", "v0.1.5", "v0.1.0", "v0.1.3", "v0.1.1", "v0.1.4"]
            .map { try makeNote(tagName: $0) }
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(
                result: .installable(makeFeed(latestRelease: latestRelease, releaseNotes: notes))
            ),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        guard case .updateAvailable(let snapshot) = result else {
            XCTFail("Expected an available update, got \(result)")
            return
        }
        XCTAssertEqual(snapshot.releaseNotes.map(\.tagName), ["v0.1.5", "v0.1.4", "v0.1.3", "v0.1.2", "v0.1.1"])
    }

    func testReportsUpToDateForEqualVersionAndShowsLatestReleaseNote() async throws {
        let release = try makeRelease(tagName: "v0.1.1")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(
                result: .installable(
                    makeFeed(
                        latestRelease: release,
                        releaseNotes: [try makeNote(tagName: "v0.1.0"), release.releaseNote]
                    )
                )
            ),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.1")
        )

        let result = await checker.checkForUpdates()

        let currentVersion = try XCTUnwrap(AppUpdateVersion(string: "0.1.1"))
        XCTAssertEqual(
            result,
            .upToDate(
                AppUpdateCheckSnapshot(
                    latestRelease: release,
                    currentVersion: currentVersion,
                    releaseNotes: [release.releaseNote]
                )
            )
        )
    }

    func testReportsUpToDateForOlderLatestVersionAndShowsLatestReleaseNote() async throws {
        let release = try makeRelease(tagName: "v0.0.9")
        let checker = AppUpdateChecker(
            releaseClient: StaticAppUpdateReleaseClient(result: .installable(makeFeed(latestRelease: release))),
            versionProvider: StaticAppVersionProvider(versionString: "0.1.0")
        )

        let result = await checker.checkForUpdates()

        let currentVersion = try XCTUnwrap(AppUpdateVersion(string: "0.1.0"))
        XCTAssertEqual(
            result,
            .upToDate(
                AppUpdateCheckSnapshot(
                    latestRelease: release,
                    currentVersion: currentVersion,
                    releaseNotes: [release.releaseNote]
                )
            )
        )
    }

    func testReportsMalformedCurrentVersionWithoutCallingReleaseClient() async {
        let client = RecordingAppUpdateReleaseClient(result: .unavailable(.privateOrNotFound))
        let checker = AppUpdateChecker(
            releaseClient: client,
            versionProvider: StaticAppVersionProvider(versionString: "debug")
        )

        let result = await checker.checkForUpdates()

        XCTAssertEqual(result, .unavailable(.malformedVersion("debug")))
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 0)
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

private actor RecordingAppUpdateReleaseClient: AppUpdateReleaseClient {
    private let result: AppUpdateReleaseLookupResult
    private var calls = 0

    init(result: AppUpdateReleaseLookupResult) {
        self.result = result
    }

    func latestRelease() async -> AppUpdateReleaseLookupResult {
        calls += 1
        return result
    }

    func callCount() -> Int {
        calls
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

private func makeFeed(
    latestRelease: AppUpdateRelease,
    releaseNotes: [AppUpdateReleaseNote]? = nil
) -> AppUpdateReleaseFeed {
    AppUpdateReleaseFeed(
        latestRelease: latestRelease,
        releaseNotes: releaseNotes ?? [latestRelease.releaseNote]
    )
}

private func makeNote(tagName: String) throws -> AppUpdateReleaseNote {
    AppUpdateReleaseNote(
        tagName: tagName,
        version: try XCTUnwrap(AppUpdateVersion(string: tagName)),
        changelogMarkdown: "Changes for \(tagName)"
    )
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
            size: 123,
            digest: try XCTUnwrap(AppUpdateReleaseAssetDigest(sha256HexDigest: String(repeating: "a", count: 64)))
        )
    )
}
