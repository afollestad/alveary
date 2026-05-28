import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitFallbackDeferredRuntimeStopsBeforeApproval() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DeferredThenMessageAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-stops-before-approval"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let maybeApprovalEvent = try await firstEvent(from: subscription.stream, description: "AgentCLIKit fallback approval event")
        let approvalEvent = try XCTUnwrap(maybeApprovalEvent)
        guard case .toolApprovalRequested = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitUntil("expected fallback approval to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        try await waitUntil("expected AgentCLIKit deferred runtime to stop before approval", timeout: .seconds(1)) {
            await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))?.isProcessRunning == false
        }

        XCTAssertEqual(manager.status(for: conversationId), .waitingForUser)
        await manager.kill(conversationId: conversationId)
    }
}
