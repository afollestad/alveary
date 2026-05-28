import AgentCLIKit
import XCTest

final class AgentCLIKitDependencyPinTests: XCTestCase {
    func testProjectPinsPushedAgentCLIKitMigrationCommit() throws {
        let projectYAML = try Self.projectYAML()

        XCTAssertTrue(projectYAML.contains(#"revision: "011b62629f8b5d86e96ccf69798f945b2e2e2e7b""#))
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
