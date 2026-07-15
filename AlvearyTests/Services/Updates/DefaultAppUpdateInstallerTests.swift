import XCTest

@testable import Alveary

final class DefaultAppUpdateInstallerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Default App Update Installer Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testSuccessfulHelperQuarantinesMetadataBeforeRelaunchAndCleansArtifacts() throws {
        let fixture = try makeFixture(
            copyScript: #"""
            #!/bin/zsh
            /usr/bin/ditto "$1" "$2"
            """#,
            openScript: #"""
            #!/bin/zsh
            echo "$1" >> "$OPEN_INVOCATIONS_FILE"
            if [ -e "$EXPECTED_METADATA_FILE" ]; then
              exit 41
            fi
            exit 0
            """#
        )

        let status = try fixture.run()

        XCTAssertEqual(status, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("new.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.metadataURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.quarantinedMetadataURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagedDirectoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupAppURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.helperURL.path))
        XCTAssertEqual(try fixture.openInvocations(), [fixture.targetAppURL.path])
    }

    func testCopyFailureRestoresAppAndMetadataAndRetainsStagedUpdate() throws {
        let fixture = try makeFixture(
            copyScript: #"""
            #!/bin/zsh
            exit 1
            """#,
            openScript: recordingOpenScript
        )

        let status = try fixture.run()

        XCTAssertEqual(status, 1)
        try assertRollbackState(fixture)
        XCTAssertEqual(try fixture.openInvocations(), [fixture.targetAppURL.path])
    }

    func testRelaunchFailureRestoresAppAndMetadataAndRetainsStagedUpdate() throws {
        let fixture = try makeFixture(
            copyScript: #"""
            #!/bin/zsh
            /usr/bin/ditto "$1" "$2"
            """#,
            openScript: #"""
            #!/bin/zsh
            echo "$1" >> "$OPEN_INVOCATIONS_FILE"
            exit 1
            """#
        )

        let status = try fixture.run()

        XCTAssertEqual(status, 1)
        try assertRollbackState(fixture)
        XCTAssertEqual(
            try fixture.openInvocations(),
            [fixture.targetAppURL.path, fixture.targetAppURL.path]
        )
    }

    func testMetadataQuarantineFailureLeavesInstalledAndStagedAppsUntouched() throws {
        let fixture = try makeFixture(
            copyScript: #"""
            #!/bin/zsh
            exit 42
            """#,
            openScript: recordingOpenScript
        )
        try FileManager.default.createDirectory(at: fixture.quarantinedMetadataURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: fixture.quarantinedMetadataURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixture.quarantinedMetadataURL.path
            )
        }

        let status = try fixture.run()

        XCTAssertEqual(status, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("new.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.metadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagedAppURL.appendingPathComponent("new.txt").path))
        XCTAssertEqual(try fixture.openInvocations(), [fixture.targetAppURL.path])
        XCTAssertTrue(try String(contentsOf: fixture.logURL, encoding: .utf8).contains("Could not quarantine staged update metadata"))
    }
}

private extension DefaultAppUpdateInstallerTests {
    var recordingOpenScript: String {
        #"""
        #!/bin/zsh
        echo "$1" >> "$OPEN_INVOCATIONS_FILE"
        exit 0
        """#
    }

    func makeFixture(copyScript: String, openScript: String) throws -> AppUpdateHelperFixture {
        let updatesDirectory = temporaryDirectory.appendingPathComponent("Updates", isDirectory: true)
        let stagedDirectoryURL = updatesDirectory
            .appendingPathComponent("Staged", isDirectory: true)
            .appendingPathComponent("v0.1.1", isDirectory: true)
        let stagedAppURL = stagedDirectoryURL.appendingPathComponent("Alveary.app", isDirectory: true)
        let targetAppURL = temporaryDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Alveary.app", isDirectory: true)
        let backupAppURL = temporaryDirectory.appendingPathComponent(".Alveary.app.backup", isDirectory: true)
        let metadataURL = updatesDirectory.appendingPathComponent("staged-update.json")
        let quarantinedMetadataURL = updatesDirectory.appendingPathComponent("staged-update.installing-test.json")
        let helperURL = updatesDirectory.appendingPathComponent("install-helper.zsh")
        let logURL = updatesDirectory.appendingPathComponent("install.log")
        let openInvocationsURL = updatesDirectory.appendingPathComponent("open-invocations.txt")

        try FileManager.default.createDirectory(at: stagedAppURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetAppURL, withIntermediateDirectories: true)
        try "new".write(to: stagedAppURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: targetAppURL.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        try "metadata".write(to: metadataURL, atomically: true, encoding: .utf8)

        let copyExecutableURL = try writeExecutable(named: "copy.zsh", contents: copyScript)
        let openExecutableURL = try writeExecutable(named: "open.zsh", contents: openScript)
        let script = AppUpdateInstallHelperScript(
            copyExecutableURL: copyExecutableURL,
            openExecutableURL: openExecutableURL,
            relaunchGraceSeconds: 0
        )
        try script.contents.write(to: helperURL, atomically: true, encoding: .utf8)

        return AppUpdateHelperFixture(
            script: script,
            stagedAppURL: stagedAppURL,
            stagedDirectoryURL: stagedDirectoryURL,
            targetAppURL: targetAppURL,
            backupAppURL: backupAppURL,
            logURL: logURL,
            metadataURL: metadataURL,
            quarantinedMetadataURL: quarantinedMetadataURL,
            helperURL: helperURL,
            openInvocationsURL: openInvocationsURL
        )
    }

    func writeExecutable(named name: String, contents: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func assertRollbackState(_ fixture: AppUpdateHelperFixture) throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.targetAppURL.appendingPathComponent("new.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.metadataURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.quarantinedMetadataURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.stagedAppURL.appendingPathComponent("new.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupAppURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.helperURL.path))
    }
}

private struct AppUpdateHelperFixture {
    let script: AppUpdateInstallHelperScript
    let stagedAppURL: URL
    let stagedDirectoryURL: URL
    let targetAppURL: URL
    let backupAppURL: URL
    let logURL: URL
    let metadataURL: URL
    let quarantinedMetadataURL: URL
    let helperURL: URL
    let openInvocationsURL: URL

    func run() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helperURL.path] + script.arguments(
            for: AppUpdateInstallHelperInvocation(
                runningProcessIdentifier: Int32.max,
                stagedAppURL: stagedAppURL,
                stagedDirectoryURL: stagedDirectoryURL,
                targetAppURL: targetAppURL,
                backupAppURL: backupAppURL,
                logURL: logURL,
                metadataURL: metadataURL,
                quarantinedMetadataURL: quarantinedMetadataURL,
                helperURL: helperURL
            )
        )
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "EXPECTED_METADATA_FILE": metadataURL.path,
                "OPEN_INVOCATIONS_FILE": openInvocationsURL.path
            ],
            uniquingKeysWith: { _, fixtureValue in fixtureValue }
        )
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func openInvocations() throws -> [String] {
        guard FileManager.default.fileExists(atPath: openInvocationsURL.path) else {
            return []
        }
        return try String(contentsOf: openInvocationsURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}
