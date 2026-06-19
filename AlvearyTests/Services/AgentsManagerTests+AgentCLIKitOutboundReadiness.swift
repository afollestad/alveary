import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension AgentsManagerTests {
    func testAgentCLIKitCancelledButRunningRuntimeRequiresRespawnForOutbound() {
        let status = AgentCLIKit.AgentRuntimeStatus(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: "agentclikit-cancelled-running-readiness"),
            providerId: .claude,
            generation: 1,
            state: .cancelled,
            lastEventIndex: 1,
            providerSessionId: nil,
            processIdentifier: 12_345,
            isProcessRunning: true
        )

        let readiness = agentCLIKitOutboundReadiness(for: status)

        XCTAssertEqual(readiness, .respawnRequired)
    }

    func testAgentCLIKitPendingInteractionBlocksOutboundReadiness() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-pending-interaction-readiness"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))

        try await waitUntil("expected AgentCLIKit runtime to wait on approval") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.waitingState == .approval
        }

        let readiness = await manager.outboundReadiness(conversationId: conversationId)
        XCTAssertEqual(readiness, .blocked(reason: "Approve or deny the pending tool use before sending another message"))

        await manager.kill(conversationId: conversationId)
    }
}
