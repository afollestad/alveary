import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitFailedReconfigureRestoresExistingSubscription() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: FailedReplacementAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-failed-reconfigure"

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: "/tmp")
        )
        do {
            try await manager.reconfigureSession(
                conversationId: conversationId,
                config: spawnConfig(workingDirectory: "/tmp")
            )
            XCTFail("Expected AgentCLIKit reconfigure to fail.")
        } catch {
            // Expected: the replacement launch fails while AgentCLIKit keeps the previous process alive.
        }
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let event = try await nextEvent(
            from: subscription.stream,
            description: "old AgentCLIKit event after failed reconfigure"
        )
        let runtimeStatus = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))

        XCTAssertEqual(event, .message(role: "assistant", content: "old-after-failed-reconfigure", parentToolUseId: nil))
        XCTAssertEqual(runtimeStatus?.state, .running)
        XCTAssertEqual(manager.status(for: conversationId), .error)
        await manager.kill(conversationId: conversationId)
    }
}
