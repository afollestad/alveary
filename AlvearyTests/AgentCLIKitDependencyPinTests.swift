import AgentCLIKit
import XCTest

final class AgentCLIKitDependencyPinTests: XCTestCase {
    func testProjectPinsPushedAgentCLIKitMigrationCommit() throws {
        let projectYAML = try Self.projectYAML()

        XCTAssertTrue(projectYAML.contains(#"revision: "7d0e0159724bc55fa5a1692c8f88d593a9ec9338""#))
        XCTAssertEqual(ClaudeProviderAdapter.providerId.rawValue, "claude")
    }

    private static func projectYAML() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
    }
}
