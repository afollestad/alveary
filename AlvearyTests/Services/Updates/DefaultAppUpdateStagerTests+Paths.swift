import XCTest

@testable import Alveary

extension DefaultAppUpdateStagerTests {
    func testOutsideRootMetadataThrowsWithoutRemovingExternalApp() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.2")
        let externalAppURL = temporaryDirectory
            .appendingPathComponent("External", isDirectory: true)
            .appendingPathComponent("Alveary.app", isDirectory: true)
        let sentinelURL = externalAppURL.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: externalAppURL, withIntermediateDirectories: true)
        try "keep".write(to: sentinelURL, atomically: true, encoding: .utf8)
        try writeMetadata(release: release, appBundleURL: externalAppURL)
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.2", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected outside-root staged app to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged app is outside Alveary's update storage.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }

    func testTraversalMetadataThrowsWithoutRemovingManagedApp() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.2")
        let stagedAppURL = managedStagedAppURL(tagName: release.tagName)
        let sentinelURL = stagedAppURL.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: stagedAppURL, withIntermediateDirectories: true)
        try "keep".write(to: sentinelURL, atomically: true, encoding: .utf8)
        let traversalAppURL = URL(
            fileURLWithPath: updatesDirectory
                .appendingPathComponent("Staged/placeholder/../v0.1.2/Alveary.app")
                .path,
            isDirectory: true
        )
        try writeMetadata(release: release, appBundleURL: traversalAppURL)
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.2", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected traversing staged app path to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged app is outside Alveary's update storage.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }

    func testSymlinkedManagedDirectoryThrowsWithoutRemovingExternalApp() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.2")
        let externalDirectory = temporaryDirectory.appendingPathComponent("ExternalStage", isDirectory: true)
        let externalAppURL = externalDirectory.appendingPathComponent("Alveary.app", isDirectory: true)
        let sentinelURL = externalAppURL.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: externalAppURL, withIntermediateDirectories: true)
        try "keep".write(to: sentinelURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: updatesDirectory.appendingPathComponent("Staged", isDirectory: true),
            withIntermediateDirectories: true
        )
        let managedDirectory = managedStagedAppURL(tagName: release.tagName).deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: managedDirectory, withDestinationURL: externalDirectory)
        try writeMetadata(
            release: release,
            appBundleURL: managedDirectory.appendingPathComponent("Alveary.app", isDirectory: true)
        )
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.2", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected symlinked staged directory to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged app is outside Alveary's update storage.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }

    func testSymlinkedManagedDirectoryToSiblingThrowsWithoutRemovingSiblingApp() async throws {
        let release = try makeManagerTestRelease(tagName: "v0.1.2")
        let siblingAppURL = managedStagedAppURL(tagName: "v0.1.1")
        let sentinelURL = siblingAppURL.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: siblingAppURL, withIntermediateDirectories: true)
        try "keep".write(to: sentinelURL, atomically: true, encoding: .utf8)
        let managedDirectory = managedStagedAppURL(tagName: release.tagName).deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(
            at: managedDirectory,
            withDestinationURL: siblingAppURL.deletingLastPathComponent()
        )
        try writeMetadata(
            release: release,
            appBundleURL: managedDirectory.appendingPathComponent("Alveary.app", isDirectory: true)
        )
        let shell = MockShellRunner()
        let stager = try makeStager(currentVersion: "0.1.2", shellRunner: shell)

        do {
            _ = try await stager.loadValidatedStagedUpdate()
            XCTFail("Expected internally symlinked staged directory to fail.")
        } catch let failure as AppUpdateFailure {
            XCTAssertEqual(failure.message, "The staged app is outside Alveary's update storage.")
        }
        let invocations = await shell.invocations

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertTrue(invocations.isEmpty)
    }
}
