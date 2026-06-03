import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

final class ProviderSetupServiceTests: XCTestCase {
    func testPrepareForSpawnForClaudeWritesTrustEntry() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")

        await fixture.service.prepareForSpawn(
            providerId: "claude",
            workingDirectory: workingDirectory.path,
            autoTrust: true
        )

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

        XCTAssertFalse(FileManager.default.fileExists(atPath: workingDirectory.appendingPathComponent(".claude/settings.local.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.globalConfigURL.path))
    }

    func testTrustProjectUpdatesClaudeTrustStatus() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")

        let isTrustedBefore = await fixture.service.isTrustedProject(
            providerId: "claude",
            workingDirectory: workingDirectory.path
        )
        XCTAssertFalse(isTrustedBefore)

        await fixture.service.trustProject(
            providerId: "claude",
            workingDirectory: workingDirectory.path
        )

        let isTrustedAfter = await fixture.service.isTrustedProject(
            providerId: "claude",
            workingDirectory: workingDirectory.path
        )
        XCTAssertTrue(isTrustedAfter)
        XCTAssertEqual(
            fixture.service.cachedProjectTrustStatus(providerId: "claude", workingDirectory: workingDirectory.path),
            true
        )
    }

    func testCachedProjectTrustStatusUsesAgentCLIKitTrustCache() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")

        XCTAssertEqual(
            fixture.service.cachedProjectTrustStatus(providerId: "claude", workingDirectory: workingDirectory.path),
            false
        )

        await fixture.service.trustProject(
            providerId: "claude",
            workingDirectory: workingDirectory.path
        )

        XCTAssertEqual(
            fixture.service.cachedProjectTrustStatus(providerId: "claude", workingDirectory: workingDirectory.path),
            true
        )
    }

    func testProjectTrustUpdatesForwardClaudeConfigSnapshots() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "worktree")
        let recorder = TrustUpdateRecorder()
        let updates = await fixture.service.projectTrustUpdates()
        let task = Task {
            for await _ in updates {
                await recorder.record()
            }
        }
        defer {
            task.cancel()
        }

        _ = await recorder.waitForCount(1)

        await fixture.service.trustProject(
            providerId: "claude",
            workingDirectory: workingDirectory.path
        )

        let updateCount = await recorder.waitForCount(2)
        XCTAssertGreaterThanOrEqual(updateCount, 2)
    }

    func testOtherProvidersDoNotRequireProjectTrust() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")

        let isTrusted = await fixture.service.isTrustedProject(
            providerId: "codex",
            workingDirectory: workingDirectory.path
        )

        XCTAssertTrue(isTrusted)
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
        let store = AgentCLIKit.ClaudeConfigStore(homeDirectoryURL: homeDirectory)
        let setup = AgentCLIKit.ClaudeProviderSetup(configStore: store)
        return TestFixture(
            homeDirectory: homeDirectory,
            service: DefaultProviderSetupService(
                projectTrustService: AgentCLIKit.DefaultAgentProjectTrustService(setups: [setup]),
                projectTrustUpdates: {
                    let snapshots = await store.snapshots()
                    return AsyncStream { continuation in
                        let task = Task {
                            for await _ in snapshots {
                                continuation.yield(())
                            }
                            continuation.finish()
                        }
                        continuation.onTermination = { _ in
                            task.cancel()
                        }
                    }
                }
            )
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

private actor TrustUpdateRecorder {
    private var count = 0

    func record() {
        count += 1
    }

    func waitForCount(_ expectedCount: Int) async -> Int {
        for _ in 0..<100 where count < expectedCount {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return count
    }
}
