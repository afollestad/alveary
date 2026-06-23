import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitStartGoalUsesExistingSessionRuntimeAPI() async throws {
        let recorder = GoalStartingAgentCLIKitRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: GoalStartingAgentCLIKitAdapter(recorder: recorder),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-existing-goal"

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(providerId: "codex", workingDirectory: "/tmp")
        )

        try await manager.startGoal("  Audit existing thread goal mode  ", conversationId: conversationId)

        let calls = await recorder.calls()
        XCTAssertEqual(calls, [
            .init(
                objective: "Audit existing thread goal mode",
                conversationId: conversationId
            )
        ])
        XCTAssertNotEqual(manager.status(for: conversationId), .busy)
        await manager.kill(conversationId: conversationId)
    }
}
