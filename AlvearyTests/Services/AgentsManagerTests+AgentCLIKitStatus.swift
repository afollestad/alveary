import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitRunningWithoutActiveTurnStaysIdle() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-idle-runtime-status"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }

        XCTAssertEqual(manager.status(for: conversationId), .idle)
        await manager.kill(conversationId: conversationId)
    }
}
