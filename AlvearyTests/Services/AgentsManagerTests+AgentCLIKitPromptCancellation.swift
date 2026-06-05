import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitAskUserQuestionDenyCancellationStaysIdleWhileRuntimeStillActive() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: AskUserQuestionPromptAgentCLIKitAdapter(
                postResolutionScript: "printf 'interaction:plan_exit\\n'; printf 'token:error\\n'; printf 'lifecycle:failed\\n'; sleep 1"
            ),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-cancelled-prompt-stays-idle"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AskUserQuestion prompt event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected AskUserQuestion approval request, got \(approvalEvent)")
        }
        try await waitUntil("expected prompt to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .deny),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))

        try await waitUntil("expected cancelled prompt to stay idle") {
            manager.status(for: conversationId) == .idle
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(manager.status(for: conversationId), .idle)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitAskUserQuestionAllowStillMarksBusy() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: AskUserQuestionPromptAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-answered-prompt-stays-busy"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AskUserQuestion prompt event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected AskUserQuestion approval request, got \(approvalEvent)")
        }
        try await waitUntil("expected prompt to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

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

        XCTAssertEqual(manager.status(for: conversationId), .busy)
        await manager.kill(conversationId: conversationId)
    }
}

private struct AskUserQuestionPromptAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let postResolutionScript: String

    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    init(postResolutionScript: String = "sleep 1") {
        self.postResolutionScript = postResolutionScript
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf 'interaction:prompt\\n'; read resolution; \(postResolutionScript)"
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        switch line {
        case "interaction:prompt":
            return [.interaction(AgentCLIKit.AgentInteractionEvent(
                id: "prompt-1",
                kind: .prompt,
                prompt: "Pick one",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("AskUserQuestion"),
                    "tool_input": .object([
                        "questions": .array([
                            .object([
                                "question": .string("Pick one"),
                                "options": .array([.object(["label": .string("A")])])
                            ])
                        ])
                    ])
                ]
            ))]
        case "interaction:plan_exit":
            return [.interaction(AgentCLIKit.AgentInteractionEvent(
                id: "plan-exit-1",
                kind: .planModeExit,
                prompt: "Implement this plan?",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("ExitPlanMode"),
                    "tool_input": .object([:])
                ]
            ))]
        case "token:error":
            return [.usage(AgentCLIKit.AgentUsageEvent(
                model: nil,
                inputTokens: 0,
                outputTokens: 0,
                durationMs: 1,
                stopReason: "failed",
                isTerminal: true,
                isError: true
            ))]
        case "lifecycle:failed":
            return [.lifecycle(AgentCLIKit.AgentLifecycleEvent(
                state: .failed,
                message: "Agent process failed"
            ))]
        default:
            return []
        }
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .userMessage, .interrupt:
            Data()
        case .interactionResolution(let resolution):
            Data("\(resolution.outcome.rawValue)\n".utf8)
        }
    }
}
