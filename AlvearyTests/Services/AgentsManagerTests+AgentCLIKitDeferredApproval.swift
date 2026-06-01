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

    func testAgentCLIKitRestoredDeferredApprovalResumesWithoutTrackedProcess() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: RestoredApprovalCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-restored-deferred-approval"
        let approval = ToolApprovalRequest(
            sessionId: "session-restored",
            toolUseId: "prompt-restored",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A"}]}]}"#
        )

        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(
                decision: .allow,
                updatedInput: #"{"answers":{"Pick one":"A"},"questions":[{"question":"Pick one","options":[{"label":"A"}]}]}"#
            ),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))

        var maybeSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected restored deferred approval to install resumed buffer") {
            maybeSubscription = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            return maybeSubscription != nil
        }
        let subscription = try XCTUnwrap(maybeSubscription)
        let resumedEvent = try await nextEvent(from: subscription.stream, description: "restored deferred approval resumed event")

        XCTAssertEqual(resumedEvent, .message(role: "assistant", content: "restored-resumed", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitRestoredAskUserQuestionSendsRuntimeResolutionAfterRespawn() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: RestoredPromptResolutionCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-restored-prompt-resolution"
        let approval = ToolApprovalRequest(
            sessionId: "session-restored",
            toolUseId: "prompt-restored",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A"}]}]}"#
        )

        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(
                decision: .allow,
                updatedInput: #"{"answers":{"Pick one":"A"},"questions":[{"question":"Pick one","options":[{"label":"A"}]}]}"#
            ),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))

        var maybeSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected restored prompt approval to install resumed buffer") {
            maybeSubscription = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            return maybeSubscription != nil
        }
        let subscription = try XCTUnwrap(maybeSubscription)
        let resumedEvent = try await nextEvent(from: subscription.stream, description: "restored prompt resolution event")

        XCTAssertEqual(resumedEvent, .message(role: "assistant", content: "restored-resolved", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }
}
