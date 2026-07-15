import XCTest

@testable import Alveary

final class DefaultAppUpdateStagerTests: XCTestCase {
    let bundleIdentifier = "com.afollestad.alveary.update-tests"
    var temporaryDirectory: URL!
    var updatesDirectory: URL {
        temporaryDirectory.appendingPathComponent("Updates", isDirectory: true)
    }

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DefaultAppUpdateStagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testLoadReturnsNilWhenMetadataIsMissing() async throws {
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.2", shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocations

        XCTAssertNil(result)
        XCTAssertTrue(invocations.isEmpty)
    }

    func testLoadDiscardsEqualManagedStagedUpdateWithoutShellValidation() async throws {
        try await assertStaleReleaseIsDiscarded(tagName: "v0.1.2", currentVersion: "0.1.2")
    }

    func testLoadDiscardsOlderManagedStagedUpdateWithoutShellValidation() async throws {
        try await assertStaleReleaseIsDiscarded(tagName: "v0.1.1", currentVersion: "0.1.2")
    }

    func testLoadRestoresValidNewerManagedStagedUpdate() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: bundleIdentifier)
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let shell = MockShellRunner()
        await shell.enqueue(.success(successfulShellResult()))
        await shell.enqueue(.success(successfulShellResult()))
        await shell.enqueue(.success(successfulShellResult(stderr: matchingSignatureOutput)))
        await shell.enqueue(.success(successfulShellResult(stderr: matchingSignatureOutput)))
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocations

        XCTAssertEqual(result?.release, release)
        XCTAssertEqual(result?.appBundleURL, stagedAppURL)
        XCTAssertEqual(result?.metadataURL, metadataURL)
        XCTAssertEqual(invocations.count, 4)
    }

    func testLoadReturnsNilWhenMetadataDisappearsDuringNewerValidation() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: bundleIdentifier)
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let shell = AppUpdateMetadataMutatingShellRunner(
            metadataURL: metadataURL,
            mutation: .remove
        )
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocationCount

        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedAppURL.path))
        XCTAssertEqual(invocations, 4)
    }

    func testLoadReturnsNilWhenMetadataIsReplacedDuringNewerValidation() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: bundleIdentifier)
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let replacement = try prepareReplacementMetadata()
        let shell = AppUpdateMetadataMutatingShellRunner(
            metadataURL: metadataURL,
            mutation: .replace(replacement.data)
        )
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocationCount

        XCTAssertNil(result)
        XCTAssertEqual(try Data(contentsOf: metadataURL), replacement.data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.appBundleURL.path))
        XCTAssertEqual(invocations, 4)
    }

    func testLoadFailureDoesNotDeleteMetadataReplacedDuringValidation() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: bundleIdentifier)
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let replacement = try prepareReplacementMetadata()
        let shell = AppUpdateMetadataMutatingShellRunner(
            metadataURL: metadataURL,
            mutation: .replace(replacement.data),
            failFirstInvocation: true
        )
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocationCount

        XCTAssertNil(result)
        XCTAssertEqual(try Data(contentsOf: metadataURL), replacement.data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.appBundleURL.path))
        XCTAssertEqual(invocations, 1)
    }

    func testFreshEqualDownloadRemainsRejected() async throws {
        try await assertFreshReleaseIsRejected(tagName: "v0.1.1", currentVersion: "0.1.1")
    }

    func testFreshOlderDownloadRemainsRejected() async throws {
        try await assertFreshReleaseIsRejected(tagName: "v0.1.1", currentVersion: "0.1.2")
    }

    func testFreshNewerDownloadStagesManagedAppAndMetadata() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let downloadedZIPURL = temporaryDirectory.appendingPathComponent("Alveary.app.zip")
        try Data("zip".utf8).write(to: downloadedZIPURL)
        let shell = AppUpdateExtractingShellRunner(
            extractedVersion: "0.1.1",
            bundleIdentifier: bundleIdentifier
        )
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        let result = try await stager.stageDownloadedUpdate(
            release: release,
            downloadedZIPURL: downloadedZIPURL
        )

        XCTAssertEqual(result.appBundleURL, managedStagedAppURL(tagName: release.tagName))
        XCTAssertEqual(result.metadataURL, metadataURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appBundleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedZIPURL.path))
    }

    func testMalformedMetadataStillThrowsAndRemovesCanonicalMetadata() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try FileManager.default.createDirectory(at: stagedAppURL, withIntermediateDirectories: true)
        try writeMetadata(release: release, appBundleURL: stagedAppURL, assetDigest: "invalid")
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected malformed metadata to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged update metadata has an invalid asset digest.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedAppURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }

    func testNewerBundleIdentityFailureStillThrows() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: "com.example.other")
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.0", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected bundle identity validation to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged app bundle identifier does not match Alveary.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedAppURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }

}

extension DefaultAppUpdateStagerTests {
    var metadataURL: URL {
        updatesDirectory.appendingPathComponent("staged-update.json")
    }

    var matchingSignatureOutput: String {
        """
        Authority=Developer ID Application: Alveary Tests
        TeamIdentifier=TESTTEAM
        """
    }

    func makeStager(
        currentVersion: String,
        shellRunner: any ShellRunner
    ) throws -> DefaultAppUpdateStager {
        let currentAppURL = temporaryDirectory
            .appendingPathComponent("Current-\(UUID().uuidString).app", isDirectory: true)
        try writeTestAppBundle(
            at: currentAppURL,
            version: currentVersion,
            bundleIdentifier: bundleIdentifier
        )
        return DefaultAppUpdateStager(
            updatesDirectory: updatesDirectory,
            shellRunner: shellRunner,
            bundle: try XCTUnwrap(Bundle(url: currentAppURL)),
            now: { Date(timeIntervalSince1970: 200) }
        )
    }

    func managedStagedAppURL(tagName: String) -> URL {
        updatesDirectory
            .appendingPathComponent("Staged", isDirectory: true)
            .appendingPathComponent(tagName, isDirectory: true)
            .appendingPathComponent("Alveary.app", isDirectory: true)
    }

    func writeMetadata(
        release: AppUpdateRelease,
        appBundleURL: URL,
        assetDigest: String? = nil
    ) throws {
        let fixture = AppUpdateStagedMetadataFixture(
            tagName: release.tagName,
            version: release.version.description,
            changelogMarkdown: release.changelogMarkdown,
            htmlURL: release.htmlURL,
            repositoryHTMLURL: release.repositoryHTMLURL,
            assetName: release.asset.name,
            assetAPIURL: release.asset.apiURL,
            assetDownloadURL: release.asset.downloadURL,
            assetSize: release.asset.size,
            assetDigest: assetDigest ?? release.asset.digest.gitHubDigest,
            appBundleURL: appBundleURL,
            stagedAt: Date(timeIntervalSince1970: 200)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        try encoder.encode(fixture).write(to: metadataURL, options: [.atomic])
    }

    func assertStaleReleaseIsDiscarded(tagName: String, currentVersion: String) async throws {
        let release = try makeManagerTestRelease(tagName: tagName)
        let stagedAppURL = managedStagedAppURL(tagName: tagName)
        let sentinelURL = stagedAppURL.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: stagedAppURL, withIntermediateDirectories: true)
        try "remove".write(to: sentinelURL, atomically: true, encoding: .utf8)
        try writeMetadata(release: release, appBundleURL: stagedAppURL)
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: currentVersion, shellRunner: shell)

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocations

        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedAppURL.deletingLastPathComponent().path))
        XCTAssertTrue(invocations.isEmpty)
    }

    func assertFreshReleaseIsRejected(tagName: String, currentVersion: String) async throws {
        let release = try makeManagerTestRelease(tagName: tagName)
        let downloadedZIPURL = temporaryDirectory.appendingPathComponent("Alveary.app.zip")
        try Data("zip".utf8).write(to: downloadedZIPURL)
        let shell = AppUpdateExtractingShellRunner(
            extractedVersion: release.version.description,
            bundleIdentifier: bundleIdentifier
        )
        let stager = try makeStager(currentVersion: currentVersion, shellRunner: shell)

        do {
            _ = try await stager.stageDownloadedUpdate(release: release, downloadedZIPURL: downloadedZIPURL)
            XCTFail("Expected equal or older downloaded update to be rejected.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged update is not newer than this Alveary build.")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadedZIPURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
    }

    func prepareReplacementMetadata() throws -> (data: Data, appBundleURL: URL) {
        let originalData = try Data(contentsOf: metadataURL)
        let replacementRelease = try makeManagerTestRelease(tagName: "v0.1.2")
        let replacementAppURL = managedStagedAppURL(tagName: replacementRelease.tagName)
        try writeTestAppBundle(
            at: replacementAppURL,
            version: replacementRelease.version.description,
            bundleIdentifier: bundleIdentifier
        )
        try writeMetadata(release: replacementRelease, appBundleURL: replacementAppURL)
        let replacementData = try Data(contentsOf: metadataURL)
        try originalData.write(to: metadataURL, options: [.atomic])
        return (replacementData, replacementAppURL)
    }
}

private struct AppUpdateStagedMetadataFixture: Encodable {
    let tagName: String
    let version: String
    let changelogMarkdown: String
    let htmlURL: URL
    let repositoryHTMLURL: URL
    let assetName: String
    let assetAPIURL: URL?
    let assetDownloadURL: URL
    let assetSize: Int?
    let assetDigest: String
    let appBundleURL: URL
    let stagedAt: Date
}

private actor AppUpdateExtractingShellRunner: ShellRunner {
    let extractedVersion: String
    let bundleIdentifier: String

    init(extractedVersion: String, bundleIdentifier: String) {
        self.extractedVersion = extractedVersion
        self.bundleIdentifier = bundleIdentifier
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        if executable == "/usr/bin/ditto", args.count == 4 {
            let extractedAppURL = URL(fileURLWithPath: args[3], isDirectory: true)
                .appendingPathComponent("Alveary.app", isDirectory: true)
            try writeTestAppBundle(
                at: extractedAppURL,
                version: extractedVersion,
                bundleIdentifier: bundleIdentifier
            )
        }
        if executable == "/usr/bin/codesign", args.first == "-dv" {
            return successfulShellResult(
                stderr: """
                Authority=Developer ID Application: Alveary Tests
                TeamIdentifier=TESTTEAM
                """
            )
        }
        return successfulShellResult()
    }
}

private actor AppUpdateMetadataMutatingShellRunner: ShellRunner {
    enum Mutation: Sendable {
        case remove
        case replace(Data)
    }

    let metadataURL: URL
    let mutation: Mutation
    let failFirstInvocation: Bool
    private(set) var invocationCount = 0

    init(
        metadataURL: URL,
        mutation: Mutation,
        failFirstInvocation: Bool = false
    ) {
        self.metadataURL = metadataURL
        self.mutation = mutation
        self.failFirstInvocation = failFirstInvocation
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        invocationCount += 1
        if invocationCount == 1 {
            switch mutation {
            case .remove:
                try FileManager.default.removeItem(at: metadataURL)
            case .replace(let data):
                try data.write(to: metadataURL, options: [.atomic])
            }
            if failFirstInvocation {
                return ShellResult(
                    stdout: "",
                    stderr: "invalid signature",
                    exitCode: 1,
                    stdoutWasTruncated: false,
                    stderrWasTruncated: false
                )
            }
        }
        if executable == "/usr/bin/codesign", args.first == "-dv" {
            return successfulShellResult(
                stderr: """
                Authority=Developer ID Application: Alveary Tests
                TeamIdentifier=TESTTEAM
                """
            )
        }
        return successfulShellResult()
    }
}

private func writeTestAppBundle(
    at appURL: URL,
    version: String,
    bundleIdentifier: String
) throws {
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableURL = contentsURL
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent("Alveary")
    try FileManager.default.createDirectory(
        at: executableURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: executableURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    let info: [String: Any] = [
        "CFBundleExecutable": "Alveary",
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": "1"
    ]
    let infoData = try PropertyListSerialization.data(
        fromPropertyList: info,
        format: .xml,
        options: 0
    )
    try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
}

private func successfulShellResult(stderr: String = "") -> ShellResult {
    ShellResult(
        stdout: "",
        stderr: stderr,
        exitCode: 0,
        stdoutWasTruncated: false,
        stderrWasTruncated: false
    )
}
