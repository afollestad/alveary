import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitInteractionResolutionCarriesExitPlanModeDeniedResponseText() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let approval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "exit-plan-1",
            toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan"}"##
        )

        let resolution = try await manager.agentCLIKitInteractionResolution(
            for: approval,
            resolution: ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            )
        )

        XCTAssertEqual(resolution.outcome, .denied)
        XCTAssertEqual(resolution.responseText, ExitPlanModeDenialPolicy.deniedResponseText)
    }

    func testAgentCLIKitInteractionResolutionDoesNotCarryDeniedResponseTextForSiblingTools() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let approval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "bash-1",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )

        let resolution = try await manager.agentCLIKitInteractionResolution(
            for: approval,
            resolution: ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            )
        )

        XCTAssertEqual(resolution.outcome, .denied)
        XCTAssertNil(resolution.responseText)
    }

    func testLiveHookDecisionProviderUsesExitPlanDeniedResponseText() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = ExitPlanModeLiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let hookRequest = exitPlanModeLiveHookRequest(conversationId: "conversation", toolUseId: "tool-1")

        let decisionTask = Task {
            await provider.decision(for: hookRequest, interactionId: "tool-1")
        }
        try await waitUntil("expected exit-plan live hook request to publish") {
            (await recorder.requests()).isEmpty == false
        }

        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            ),
            for: ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-1")
        )
        let decision = await decisionTask.value

        XCTAssertTrue(didResolve)
        XCTAssertEqual(decision.approval, .deny)
        XCTAssertEqual(decision.reason, ExitPlanModeDenialPolicy.deniedResponseText)
    }

    func testLiveHookDecisionProviderUsesExitPlanDeniedResponseTextForPlanModeExitHook() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = ExitPlanModeLiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let hookRequest = planModeExitLiveHookRequest(conversationId: "conversation", toolUseId: "tool-1")

        let decisionTask = Task {
            await provider.decision(for: hookRequest, interactionId: "tool-1")
        }
        try await waitUntil("expected plan-mode-exit live hook request to publish") {
            (await recorder.requests()).isEmpty == false
        }

        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            ),
            for: ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-1")
        )
        let decision = await decisionTask.value
        let publishedRequests = await recorder.requests()

        XCTAssertTrue(didResolve)
        XCTAssertEqual(publishedRequests.first?.request.toolName, "ExitPlanMode")
        XCTAssertEqual(publishedRequests.first?.request.planMarkdownFallback, "Ship it")
        XCTAssertEqual(decision.approval, .deny)
        XCTAssertEqual(decision.reason, ExitPlanModeDenialPolicy.deniedResponseText)
    }

    func testLiveHookDecisionProviderKeepsGenericDeniedReasonForSiblingTools() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = ExitPlanModeLiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }

        let decisionTask = Task {
            await provider.decision(
                for: bashLiveHookRequest(conversationId: "conversation", toolUseId: "tool-1"),
                interactionId: "tool-1"
            )
        }
        try await waitUntil("expected bash live hook request to publish") {
            (await recorder.requests()).isEmpty == false
        }

        let didResolve = await provider.resolve(
            ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            ),
            for: ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-1")
        )
        let decision = await decisionTask.value

        XCTAssertTrue(didResolve)
        XCTAssertEqual(decision.approval, .deny)
        XCTAssertEqual(decision.reason, "The user denied this permission prompt in Alveary")
    }

    func testLiveHookDecisionProviderUsesExitPlanDeniedResponseTextForFutureDecision() async throws {
        let provider = AgentCLIKitLiveHookDecisionProvider(sleep: { _ in })
        let recorder = ExitPlanModeLiveHookRequestRecorder()
        await provider.setDeferredToolRequestHandler { request in
            await recorder.append(request)
        }
        let key = ClaudeToolApprovalKey(sessionId: "session-1", toolUseId: "tool-2")
        await provider.recordFutureResolution(
            ClaudeToolApprovalResolution(
                decision: .deny,
                responseText: ExitPlanModeDenialPolicy.deniedResponseText
            ),
            for: key
        )

        let decision = await provider.decision(
            for: exitPlanModeLiveHookRequest(conversationId: "conversation", toolUseId: "tool-2"),
            interactionId: "tool-2"
        )
        let publishedRequests = await recorder.requests()

        XCTAssertEqual(decision.approval, .deny)
        XCTAssertEqual(decision.reason, ExitPlanModeDenialPolicy.deniedResponseText)
        XCTAssertTrue(publishedRequests.isEmpty)
    }
}

private func exitPlanModeLiveHookRequest(conversationId: String, toolUseId: String) -> AgentCLIKit.ClaudeHookRequest {
    AgentCLIKit.ClaudeHookRequest(
        bearerToken: "token",
        hookName: "PreToolUse",
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        payload: .object([
            "session_id": .string("session-1"),
            "tool_use_id": .string(toolUseId),
            "tool_name": .string("ExitPlanMode"),
            "tool_input": .object(["plan": .string("Ship it")])
        ])
    )
}

private func planModeExitLiveHookRequest(conversationId: String, toolUseId: String) -> AgentCLIKit.ClaudeHookRequest {
    AgentCLIKit.ClaudeHookRequest(
        bearerToken: "token",
        hookName: "PlanModeExit",
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        payload: .object([
            "session_id": .string("session-1"),
            "tool_use_id": .string(toolUseId),
            "permissionMode": .string("plan"),
            "plan": .string("Ship it")
        ])
    )
}

private func bashLiveHookRequest(conversationId: String, toolUseId: String) -> AgentCLIKit.ClaudeHookRequest {
    AgentCLIKit.ClaudeHookRequest(
        bearerToken: "token",
        hookName: "PreToolUse",
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        payload: .object([
            "session_id": .string("session-1"),
            "tool_use_id": .string(toolUseId),
            "tool_name": .string("Bash"),
            "tool_input": .object(["command": .string("pwd")])
        ])
    )
}

private actor ExitPlanModeLiveHookRequestRecorder {
    private var storage: [ClaudeDeferredToolRequest] = []

    func append(_ request: ClaudeDeferredToolRequest) {
        storage.append(request)
    }

    func requests() -> [ClaudeDeferredToolRequest] {
        storage
    }
}
