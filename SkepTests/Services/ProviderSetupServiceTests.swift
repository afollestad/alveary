import Foundation
import XCTest

@testable import Skep

final class ProviderSetupServiceTests: XCTestCase {
    func testPrepareForSpawnForClaudeCreatesLocalSettingsAndTrustEntry() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")

        await fixture.service.prepareForSpawn(
            providerId: "claude",
            workingDirectory: workingDirectory.path,
            autoTrust: true
        )

        let settingsURL = workingDirectory.appendingPathComponent(".claude/settings.local.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))

        let root = try readJSON(at: fixture.globalConfigURL)
        let projects = try XCTUnwrap(root["projects"] as? [String: Any])
        let trustedProject = try XCTUnwrap(projects[CanonicalPath.normalize(workingDirectory.path)] as? [String: Any])
        XCTAssertEqual(trustedProject["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(trustedProject["hasCompletedProjectOnboarding"] as? Bool, true)
    }

    func testPrepareForSpawnSkipsTrustWriteWhenAutoTrustIsDisabled() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")

        await fixture.service.prepareForSpawn(
            providerId: "claude",
            workingDirectory: workingDirectory.path,
            autoTrust: false
        )

        let settingsURL = workingDirectory.appendingPathComponent(".claude/settings.local.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.globalConfigURL.path))
    }

    func testPrepareForSpawnForOtherProvidersIsNoOp() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")

        await fixture.service.prepareForSpawn(
            providerId: "codex",
            workingDirectory: workingDirectory.path,
            autoTrust: true
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(".claude/settings.local.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.globalConfigURL.path))
    }

    func testConcurrentPrepareForSpawnPreservesBothTrustEntries() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let firstDirectory = try fixture.makeWorkingDirectory(named: "worktree-1")
        let secondDirectory = try fixture.makeWorkingDirectory(named: "worktree-2")

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await fixture.service.prepareForSpawn(
                    providerId: "claude",
                    workingDirectory: firstDirectory.path,
                    autoTrust: true
                )
            }
            group.addTask {
                await fixture.service.prepareForSpawn(
                    providerId: "claude",
                    workingDirectory: secondDirectory.path,
                    autoTrust: true
                )
            }
        }

        let root = try readJSON(at: fixture.globalConfigURL)
        let projects = try XCTUnwrap(root["projects"] as? [String: Any])

        XCTAssertNotNil(projects[CanonicalPath.normalize(firstDirectory.path)])
        XCTAssertNotNil(projects[CanonicalPath.normalize(secondDirectory.path)])
    }

    private func makeFixture() throws -> TestFixture {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true, attributes: nil)
        let store = DefaultClaudeConfigStore(homeDirectoryURL: homeDirectory)
        return TestFixture(
            homeDirectory: homeDirectory,
            service: DefaultProviderSetupService(claudeConfigStore: store)
        )
    }

    private func readJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private struct TestFixture {
    let homeDirectory: URL
    let service: DefaultProviderSetupService

    var globalConfigURL: URL {
        homeDirectory.appendingPathComponent(".claude.json")
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: homeDirectory)
    }

    func makeWorkingDirectory(named name: String) throws -> URL {
        let workingDirectory = homeDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)
        return workingDirectory
    }
}
