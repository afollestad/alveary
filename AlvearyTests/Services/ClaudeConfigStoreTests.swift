import Foundation
import XCTest

@testable import Alveary

final class ClaudeConfigStoreTests: XCTestCase {
    func testTrustStatusReflectsTrustedProjectEntries() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")

        let isTrustedBefore = await fixture.store.isTrustedProject(path: workingDirectory.path)
        XCTAssertFalse(isTrustedBefore)

        await fixture.store.upsertTrustedProject(path: workingDirectory.path)

        let isTrustedAfter = await fixture.store.isTrustedProject(path: workingDirectory.path)
        XCTAssertTrue(isTrustedAfter)
        let snapshot = await fixture.store.currentSnapshot()
        XCTAssertTrue(snapshot.isTrustedProject(path: workingDirectory.path))
    }

    func testUpsertTrustedProjectPreservesExistingMCPServers() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")
        try writeJSON(
            [
                "mcpServers": [
                    "filesystem": [
                        "command": "npx",
                        "args": ["-y", "@modelcontextprotocol/server-filesystem"]
                    ]
                ]
            ],
            to: fixture.globalConfigURL
        )

        await fixture.store.upsertTrustedProject(path: workingDirectory.path)

        let root = try readJSON(at: fixture.globalConfigURL)
        let mcpServers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(mcpServers["filesystem"])

        let projects = try XCTUnwrap(root["projects"] as? [String: Any])
        let normalizedPath = CanonicalPath.normalize(workingDirectory.path)
        let trustedProject = try XCTUnwrap(projects[normalizedPath] as? [String: Any])
        XCTAssertEqual(trustedProject["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(trustedProject["hasCompletedProjectOnboarding"] as? Bool, true)
    }

    func testUpsertTrustedProjectDoesNotEscapePathSlashes() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")

        await fixture.store.upsertTrustedProject(path: workingDirectory.path)

        let rawConfig = try String(contentsOf: fixture.globalConfigURL, encoding: .utf8)
        XCTAssertTrue(rawConfig.contains(CanonicalPath.normalize(workingDirectory.path)))
        XCTAssertFalse(rawConfig.contains("\\/"))
    }

    func testWriteMCPServersRoundTripsAndPreservesTrustedProjects() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")
        try writeJSON(
            [
                "projects": [
                    CanonicalPath.normalize(workingDirectory.path): [
                        "hasTrustDialogAccepted": true,
                        "hasCompletedProjectOnboarding": true
                    ]
                ],
                "otherKey": ["enabled": true]
            ],
            to: fixture.globalConfigURL
        )

        let servers = [
            "github": ClaudeMCPServerConfig(
                command: "docker",
                args: ["run", "gh-server"],
                url: nil,
                headers: nil,
                env: ["GITHUB_TOKEN": "secret"]
            )
        ]

        await fixture.store.writeMCPServers(servers)

        let reread = await fixture.store.readMCPServers()
        XCTAssertEqual(reread, servers)

        let root = try readJSON(at: fixture.globalConfigURL)
        let projects = try XCTUnwrap(root["projects"] as? [String: Any])
        XCTAssertNotNil(projects[CanonicalPath.normalize(workingDirectory.path)])
        XCTAssertEqual((root["otherKey"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    func testTrustedProjectUpdatesEmitOnlyWhenConfigChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ClaudeConfigNotificationRecorder()
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")
        let observer = NotificationCenter.default.addObserver(
            forName: .claudeConfigChanged,
            object: fixture.store,
            queue: nil
        ) { notification in
            guard let snapshot = notification.userInfo?[ClaudeConfigNotificationKey.snapshot] as? ClaudeConfigSnapshot else {
                return
            }
            Task {
                await recorder.append(snapshot)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        await fixture.store.upsertTrustedProject(path: workingDirectory.path)
        await fixture.store.upsertTrustedProject(path: workingDirectory.path)

        let snapshots = await recorder.waitForSnapshots(count: 1)
        try await Task.sleep(for: .milliseconds(50))
        let finalSnapshots = await recorder.allSnapshots()
        XCTAssertEqual(finalSnapshots.count, 1)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(finalSnapshots.first?.isTrustedProject(path: workingDirectory.path) == true)
    }

    func testExternalConfigWritesEmitOnlyWhenConfigChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let recorder = ClaudeConfigNotificationRecorder()
        let workingDirectory = try fixture.makeWorkingDirectory(named: "project")
        let observer = NotificationCenter.default.addObserver(
            forName: .claudeConfigChanged,
            object: fixture.store,
            queue: nil
        ) { notification in
            guard let snapshot = notification.userInfo?[ClaudeConfigNotificationKey.snapshot] as? ClaudeConfigSnapshot else {
                return
            }
            Task {
                await recorder.append(snapshot)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        _ = await fixture.store.currentSnapshot()
        let payload: [String: Any] = [
            "projects": [
                CanonicalPath.normalize(workingDirectory.path): [
                    "hasTrustDialogAccepted": true,
                    "hasCompletedProjectOnboarding": true
                ]
            ]
        ]

        try writeJSON(payload, to: fixture.globalConfigURL)

        let snapshots = await recorder.waitForSnapshots(count: 1)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(snapshots.first?.isTrustedProject(path: workingDirectory.path) == true)

        try writeJSON(payload, to: fixture.globalConfigURL)
        try await Task.sleep(for: .milliseconds(50))

        let finalSnapshots = await recorder.allSnapshots()
        XCTAssertEqual(finalSnapshots.count, 1)
    }

    func testSnapshotStreamReplaysCacheThenEmitsChangedRefresh() async throws {
        let homeDirectory = try makeHomeDirectory()
        defer {
            try? FileManager.default.removeItem(at: homeDirectory)
        }
        let firstProject = try makeWorkingDirectory(named: "first", in: homeDirectory)
        let secondProject = try makeWorkingDirectory(named: "second", in: homeDirectory)
        let globalConfigURL = homeDirectory.appendingPathComponent(".claude.json")
        try writeJSON(
            trustedProjectsPayload([firstProject.path]),
            to: globalConfigURL
        )
        let store = DefaultClaudeConfigStore(homeDirectoryURL: homeDirectory)

        try writeJSON(
            trustedProjectsPayload([firstProject.path, secondProject.path]),
            to: globalConfigURL
        )

        let recorder = ClaudeConfigNotificationRecorder()
        let stream = await store.snapshots()
        let task = Task {
            for await snapshot in stream {
                await recorder.append(snapshot)
            }
        }
        defer {
            task.cancel()
        }

        let cachedSnapshots = await recorder.waitForSnapshots(count: 1)
        XCTAssertEqual(cachedSnapshots.count, 1)
        XCTAssertTrue(cachedSnapshots[0].isTrustedProject(path: firstProject.path))
        XCTAssertFalse(cachedSnapshots[0].isTrustedProject(path: secondProject.path))

        let refreshedSnapshot = await store.currentSnapshot()
        XCTAssertTrue(refreshedSnapshot.isTrustedProject(path: secondProject.path))

        let refreshedSnapshots = await recorder.waitForSnapshots(count: 2)
        XCTAssertEqual(refreshedSnapshots.count, 2)
        XCTAssertTrue(refreshedSnapshots[1].isTrustedProject(path: secondProject.path))

        _ = await store.currentSnapshot()
        try await Task.sleep(for: .milliseconds(50))
        let finalSnapshots = await recorder.allSnapshots()
        XCTAssertEqual(finalSnapshots.count, 2)
    }

    private func makeFixture() throws -> TestFixture {
        let homeDirectory = try makeHomeDirectory()
        return TestFixture(
            homeDirectory: homeDirectory,
            store: DefaultClaudeConfigStore(homeDirectoryURL: homeDirectory)
        )
    }

    private func makeHomeDirectory() throws -> URL {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true, attributes: nil)
        return homeDirectory
    }

    private func makeWorkingDirectory(named name: String, in homeDirectory: URL) throws -> URL {
        let workingDirectory = homeDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)
        return workingDirectory
    }

    private func trustedProjectsPayload(_ paths: [String]) -> [String: Any] {
        [
            "projects": Dictionary(
                uniqueKeysWithValues: paths.map { path in
                    (
                        CanonicalPath.normalize(path),
                        [
                            "hasTrustDialogAccepted": true,
                            "hasCompletedProjectOnboarding": true
                        ]
                    )
                }
            )
        ]
    }

    private func readJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

private actor ClaudeConfigNotificationRecorder {
    private var recordedSnapshots: [ClaudeConfigSnapshot] = []

    func append(_ snapshot: ClaudeConfigSnapshot) {
        recordedSnapshots.append(snapshot)
    }

    func waitForSnapshots(count expectedCount: Int) async -> [ClaudeConfigSnapshot] {
        for _ in 0..<100 where recordedSnapshots.count < expectedCount {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return recordedSnapshots
    }

    func allSnapshots() -> [ClaudeConfigSnapshot] {
        recordedSnapshots
    }
}

private struct TestFixture {
    let homeDirectory: URL
    let store: DefaultClaudeConfigStore

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
