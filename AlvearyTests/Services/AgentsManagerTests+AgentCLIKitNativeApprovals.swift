import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitExactBatchSessionApprovalRecordsSiblingPathGrants() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-batch-path-session-approval"
        let firstApproval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-1",
            toolName: "Read",
            toolInput: #"{"file_path":"/tmp/outside/one.txt"}"#
        )
        let secondApproval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-2",
            toolName: "Read",
            toolInput: #"{"file_path":"/tmp/outside/two.txt"}"#
        )
        let sessionApproval = try XCTUnwrap(firstApproval.sessionApprovalGrant(
            conversationId: conversationId,
            providerId: "claude",
            scope: .exact
        ))

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: firstApproval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [secondApproval],
            sessionApproval: sessionApproval,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        let firstAllowsApproval = await fixture.approvalStore.allowsSessionApproval(readSessionApprovalRequest(
            conversationId: conversationId,
            filePath: "/tmp/outside/one.txt"
        ))
        let secondAllowsApproval = await fixture.approvalStore.allowsSessionApproval(readSessionApprovalRequest(
            conversationId: conversationId,
            filePath: "/tmp/outside/two.txt"
        ))

        XCTAssertTrue(firstAllowsApproval)
        XCTAssertTrue(secondAllowsApproval)
        await manager.kill(conversationId: conversationId)
    }
}

private func readSessionApprovalRequest(
    conversationId: String,
    filePath: String
) -> AgentCLIKit.AgentSessionApprovalRequest {
    AgentCLIKit.AgentSessionApprovalRequest(
        providerId: .claude,
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        sessionId: "session-1",
        toolName: "Read",
        toolInput: .object(["file_path": .string(filePath)])
    )
}
