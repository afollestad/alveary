import Foundation
import XCTest

@testable import Skep

final class MCPConfigIOTests: XCTestCase {
    func testReadServersFiltersNonObjectEntries() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        try Data("{\"mcpServers\":{\"good\":{\"command\":\"npx\"},\"bad\":\"skip\"}}".utf8).write(to: configURL)

        let servers = try MCPConfigIO.readServers(
            from: MCPIntegrationDefinition(
                configPath: configURL.path,
                serversKeyPath: ["mcpServers"],
                format: .json,
                adapterId: "passthrough",
                supportsHttp: true
            )
        )

        XCTAssertEqual(servers.keys.sorted(), ["good"])
        XCTAssertEqual(servers["good"]?["command"] as? String, "npx")
    }

    func testWriteServersPreservesExistingKeysAndNestedObjects() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.json")
        try Data("{\"theme\":\"dark\",\"root\":{\"other\":true}}".utf8).write(to: configURL)

        try MCPConfigIO.writeServers(
            to: MCPIntegrationDefinition(
                configPath: configURL.path,
                serversKeyPath: ["root", "servers"],
                format: .json,
                adapterId: "passthrough",
                supportsHttp: true
            ),
            servers: [
                "context7": ["url": "https://mcp.context7.com/mcp"]
            ]
        )

        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        )
        XCTAssertEqual(root["theme"] as? String, "dark")
        let nested = try XCTUnwrap(root["root"] as? [String: Any])
        XCTAssertEqual(nested["other"] as? Bool, true)
        let servers = try XCTUnwrap(nested["servers"] as? [String: Any])
        XCTAssertEqual((servers["context7"] as? [String: Any])?["url"] as? String, "https://mcp.context7.com/mcp")
    }

    func testWriteServersRejectsUnsupportedTomlFormatWithoutTouchingFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        let original = "theme = \"dark\"\n[mcpServers]\nexisting = { command = \"npx\" }\n"
        try Data(original.utf8).write(to: configURL)

        XCTAssertThrowsError(
            try MCPConfigIO.writeServers(
                to: MCPIntegrationDefinition(
                    configPath: configURL.path,
                    serversKeyPath: ["mcpServers"],
                    format: .toml,
                    adapterId: "passthrough",
                    supportsHttp: false
                ),
                servers: [
                    "context7": ["url": "https://mcp.context7.com/mcp"]
                ]
            )
        ) { error in
            XCTAssertEqual(error as? MCPConfigIOError, .unsupportedWriteFormat(.toml))
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), original)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }
}
