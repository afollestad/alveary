import AgentCLIKit
import XCTest

final class AgentCLIKitDependencyPinTests: XCTestCase {
    func testProjectPinsPushedAgentCLIKitMigrationCommit() throws {
        let projectYAML = try Self.projectYAML()

        XCTAssertTrue(projectYAML.contains(#"revision: "af955ed8320514f57d7fdab2852672b93b5c358c""#))
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
