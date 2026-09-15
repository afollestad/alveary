import XCTest

@testable import Alveary

extension DefaultAppUpdateStagerTests {
    #if DEBUG
    func testDebugStorageLeavesProductionStagedUpdateUntouched() async throws {
        let profile = AppStorageProfile(
            applicationSupportBaseURL: temporaryDirectory,
            settingsDefaults: .standard,
            settingsDefaultsSuiteName: nil
        )
        let productionPaths = AppUpdateStoragePaths(
            updatesDirectory: profile.appSupportDirectory.appendingPathComponent("Updates", isDirectory: true)
        )
        let release = try makeManagerTestRelease(tagName: "v0.1.1")
        let stagedAppURL = try productionPaths.stagedAppURL(directoryName: release.tagName)
        try writeTestAppBundle(at: stagedAppURL, version: "0.1.1", bundleIdentifier: "com.afollestad.alveary")
        try writeMetadata(release: release, appBundleURL: stagedAppURL, destinationURL: productionPaths.metadataURL)
        let originalMetadata = try Data(contentsOf: productionPaths.metadataURL)
        let stagedInfoURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
        let originalStagedInfo = try Data(contentsOf: stagedInfoURL)
        let currentAppURL = temporaryDirectory.appendingPathComponent("Alveary Dev.app", isDirectory: true)
        try writeTestAppBundle(at: currentAppURL, version: "0.1.2", bundleIdentifier: "com.afollestad.alveary.debug")
        let shell = MockShellRunner()
        let stager = DefaultAppUpdateStager(
            updatesDirectory: profile.updatesDirectory,
            shellRunner: shell,
            bundle: try XCTUnwrap(Bundle(url: currentAppURL))
        )

        let result = try await stager.loadValidatedStagedUpdate()
        let invocations = await shell.invocations

        XCTAssertNil(result)
        XCTAssertTrue(invocations.isEmpty)
        XCTAssertEqual(try Data(contentsOf: productionPaths.metadataURL), originalMetadata)
        XCTAssertEqual(try Data(contentsOf: stagedInfoURL), originalStagedInfo)
    }
    #endif
}
