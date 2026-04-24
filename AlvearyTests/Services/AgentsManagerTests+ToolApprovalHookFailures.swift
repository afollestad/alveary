import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testHookFailureConsumesPendingLiveApprovalBeforeLaterResolution() async throws {
        let fixture = try makeLiveHookFailureFixture()
        defer { fixture.cleanup() }

        try await fixture.start(description: "expected initial launch before live approval failure")
        let approval = bashApprovalRequest(command: "date")
        await emitLiveApprovalAndFailure(fixture: fixture, approval: approval)

        _ = try await fixture.manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: fixture.conversationId,
                approval: approval,
                resolution: ClaudeToolApprovalResolution(decision: .allow),
                additionalApprovals: [],
                sessionApproval: nil,
                config: fixture.config
            )
        )

        try await waitUntil("expected fallback resume after failed live hook") {
            try fixture.executable.recordedLaunchArguments().count == 2
        }
        let decisions = await fixture.hookServer.decisions().map { $0.0 }
        XCTAssertEqual(decisions, [.allow])
    }
}

@MainActor
private extension AgentsManagerTests {
    func makeLiveHookFailureFixture() throws -> ApprovalFixture {
        try makeApprovalFixture(
            conversationId: "conversation-hook-live-failure-count",
            launchConfigs: [
                ClaudeHookLaunchConfig(
                    arguments: [],
                    environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
                ),
                ClaudeHookLaunchConfig(
                    arguments: [],
                    environment: ["ALVEARY_HOOK_TOKEN": "resume-token"]
                )
            ]
        )
    }

    func emitLiveApprovalAndFailure(
        fixture: ApprovalFixture,
        approval: ToolApprovalRequest
    ) async {
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(
                conversationId: fixture.conversationId,
                launchToken: "approval-token",
                request: approval
            )
        )

        guard let subscription = await fixture.manager.subscribe(conversationId: fixture.conversationId, afterIndex: 0) else {
            XCTFail("Expected live approval buffer")
            return
        }

        await fixture.manager.handleStreamEvent(
            .toolApprovalFailed(ToolApprovalFailure(
                sessionId: approval.sessionId,
                toolUseId: approval.toolUseId,
                toolName: approval.toolName,
                message: "Claude hook failed (PreToolUse:Bash): socket closed"
            )),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )
    }
}
