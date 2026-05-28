import AgentCLIKit
import XCTest

final class AgentCLIKitDependencyPinTests: XCTestCase {
    func testProjectPinsPushedAgentCLIKitMigrationCommit() throws {
        let projectYAML = try Self.projectYAML()

        XCTAssertTrue(projectYAML.contains(#"revision: "ef0e3dbb8c8dbcf1e88dd05e96c93eaf69b6df3d""#))
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
