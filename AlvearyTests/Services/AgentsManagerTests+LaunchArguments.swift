import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testLaunchArgumentsKeepOnlyAppOwnedDirectoryGrantsAndSchedulingPolicy() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let directories = ["/workspaces/project files", "/workspaces/second-root"]

        for harnessID in ["claude", "codex", "opencode"] {
            let config = Alveary.AgentSpawnConfig(
                harnessId: harnessID,
                workingDirectory: "/tmp/project",
                permissionMode: nil,
                model: nil,
                effort: nil,
                initialPrompt: nil,
                allowedDirectories: directories
            )
            let launch = try await fixture.manager.agentCLIKitSpawnConfig(config, forkSession: false, services: fixture.services)

            if harnessID == "claude" {
                XCTAssertEqual(launch.arguments, [
                    "--add-dir", "/workspaces/project files", "--add-dir", "/workspaces/second-root", "--disallowedTools", "RemoteTrigger"
                ])
                XCTAssertEqual(launch.environment["CLAUDE_CODE_DISABLE_CRON"], "1")
            } else {
                XCTAssertTrue(launch.arguments.isEmpty, harnessID)
                XCTAssertNil(launch.environment["CLAUDE_CODE_DISABLE_CRON"], harnessID)
            }
        }
    }
}
