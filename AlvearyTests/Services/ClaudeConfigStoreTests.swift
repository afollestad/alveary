import Foundation
import XCTest

@testable import Alveary

final class ClaudeConfigStoreTests: XCTestCase {
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

    private func makeFixture() throws -> TestFixture {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true, attributes: nil)
        return TestFixture(
            homeDirectory: homeDirectory,
            store: DefaultClaudeConfigStore(homeDirectoryURL: homeDirectory)
        )
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
