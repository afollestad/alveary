import Foundation
import XCTest

@testable import Alveary

final class AlvearyProjectConfigTests: XCTestCase {
    func testParsesAllSupportedFields() async throws {
        let projectURL = try makeProjectDirectory()
        try writeConfig(
            [
                "scripts": [
                    "setup": "bin/setup",
                    "setupTimeoutSeconds": 45,
                    "teardown": "bin/teardown"
                ],
                "shellSetup": "source .envrc",
                "preservePatterns": [".env", "config/*.json"],
                "actions": [
                    ["name": "Test", "command": "swift test"],
                    ["name": "Lint", "command": "swiftlint"]
                ]
            ],
            to: projectURL
        )

        let config = await AlvearyProjectConfig(projectPath: projectURL.path)

        XCTAssertEqual(config.setupScript, "bin/setup")
        XCTAssertEqual(config.setupTimeoutSeconds, 45)
        XCTAssertEqual(config.teardownScript, "bin/teardown")
        XCTAssertEqual(config.shellSetup, "source .envrc")
        XCTAssertEqual(config.preservePatterns, [".env", "config/*.json"])
        XCTAssertEqual(
            config.actions,
            [
                .init(name: "Test", command: "swift test"),
                .init(name: "Lint", command: "swiftlint")
            ]
        )
    }

    func testMissingAndMalformedConfigReturnNilFields() async throws {
        let missingProjectURL = try makeProjectDirectory()
        let missingConfig = await AlvearyProjectConfig(projectPath: missingProjectURL.path)

        assertAllFieldsNil(in: missingConfig)

        let malformedProjectURL = try makeProjectDirectory()
        try Data("{not-json".utf8).write(to: malformedProjectURL.appendingPathComponent(".alveary.json"))
        let malformedConfig = await AlvearyProjectConfig(projectPath: malformedProjectURL.path)

        assertAllFieldsNil(in: malformedConfig)
    }

    func testEmptyScriptValuesAndNonPositiveTimeoutsBecomeNil() async throws {
        let projectURL = try makeProjectDirectory()
        try writeConfig(
            [
                "scripts": [
                    "setup": "",
                    "setupTimeoutSeconds": 0,
                    "teardown": ""
                ],
                "shellSetup": "",
                "actions": [
                    ["name": "Valid", "command": "echo ok"],
                    ["name": "Missing command"]
                ]
            ],
            to: projectURL
        )

        let config = await AlvearyProjectConfig(projectPath: projectURL.path)

        XCTAssertNil(config.setupScript)
        XCTAssertNil(config.setupTimeoutSeconds)
        XCTAssertNil(config.teardownScript)
        XCTAssertNil(config.shellSetup)
        XCTAssertEqual(config.actions, [.init(name: "Valid", command: "echo ok")])
    }

    private func makeProjectDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeConfig(_ jsonObject: [String: Any], to projectURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        try data.write(to: projectURL.appendingPathComponent(".alveary.json"))
    }

    private func assertAllFieldsNil(in config: AlvearyProjectConfig) {
        XCTAssertNil(config.setupScript)
        XCTAssertNil(config.setupTimeoutSeconds)
        XCTAssertNil(config.teardownScript)
        XCTAssertNil(config.shellSetup)
        XCTAssertNil(config.preservePatterns)
        XCTAssertNil(config.actions)
    }
}
