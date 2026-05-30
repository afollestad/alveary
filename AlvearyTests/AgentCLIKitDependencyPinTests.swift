import AgentCLIKit
import XCTest

final class AgentCLIKitDependencyPinTests: XCTestCase {
    func testProjectPinsPushedAgentCLIKitMigrationCommit() throws {
        let projectYAML = try Self.projectYAML()

        XCTAssertTrue(projectYAML.contains(#"revision: "c076a67e37e3ef82aabaae8fa6541e38b43c77f7""#))
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
