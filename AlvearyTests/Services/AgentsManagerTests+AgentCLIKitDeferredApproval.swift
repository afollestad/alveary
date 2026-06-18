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

    func testAgentCLIKitFallbackParallelApprovalsSendRuntimeResolutionsAfterRespawn() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ParallelApprovalResolutionAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-parallel-fallback-resolutions"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let firstEvent = try await nextEvent(from: subscription.stream, description: "first parallel fallback approval")
        let secondEvent = try await nextEvent(from: subscription.stream, description: "second parallel fallback approval")
        guard case let .toolApprovalRequested(firstApproval) = firstEvent,
              case let .toolApprovalRequested(secondApproval) = secondEvent else {
            return XCTFail("Expected two approval requests, got \(firstEvent) and \(secondEvent)")
        }
        try await waitUntil("expected parallel fallback approvals to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        // The resumed adapter stays silent unless both approved sibling rows are sent back through
        // `AgentCLIKit` stdin after respawn. Without that, the UI can show Approved while the turn spins.
        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: firstApproval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [secondApproval],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected parallel fallback approval to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == subscription.generation ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        let messageEvent = try await nextEvent(
            from: resolvedSubscription.stream,
            description: "parallel fallback approval resumed event"
        )

        XCTAssertEqual(messageEvent, .message(role: "assistant", content: "resumed-both", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitFallbackSessionApprovalMarksRespawnedInteractionResolutionsAsSession() async throws {
        let resolutionRecorder = AgentInteractionResolutionRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: ParallelApprovalResolutionAdapter(
                providerId: .codex,
                resolutionRecorder: resolutionRecorder
            ),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-session-resolutions"

        try await manager.spawn(id: conversationId, config: spawnConfig(providerId: "codex", workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let firstEvent = try await nextEvent(from: subscription.stream, description: "first fallback session approval")
        let secondEvent = try await nextEvent(from: subscription.stream, description: "second fallback session approval")
        guard case let .toolApprovalRequested(firstApproval) = firstEvent,
              case let .toolApprovalRequested(secondApproval) = secondEvent else {
            return XCTFail("Expected two approval requests, got \(firstEvent) and \(secondEvent)")
        }
        let sessionApproval = try XCTUnwrap(firstApproval.sessionApprovalGrant(
            conversationId: conversationId,
            providerId: "codex",
            scope: .exact
        ))
        try await waitUntil("expected fallback session approvals to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: firstApproval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [secondApproval],
            sessionApproval: sessionApproval,
            config: spawnConfig(providerId: "codex", workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected fallback session approval to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == subscription.generation ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        _ = try await nextEvent(
            from: resolvedSubscription.stream,
            description: "fallback session approval resumed event"
        )
        let resolutions = await resolutionRecorder.resolutions()

        assertCodexSessionResolutionMetadata(resolutions, expectedCount: 2)
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

    func testAgentCLIKitFallbackApprovalNudgesRespawnWhenDeferredReplayMarkerMissing() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: NudgeRecoveryAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-deferred-nudge"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "deferred nudge approval")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitUntil("expected fallback approval to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        // No Claude transcript holds a deferred-tool marker for this session, so the respawn cannot
        // auto-replay the approved tool; the manager must nudge it with a recovery user message.
        _ = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected nudge respawn to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == subscription.generation ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        let messageEvent = try await nextEvent(from: resolvedSubscription.stream, description: "nudge recovery message event")

        XCTAssertEqual(messageEvent, .message(role: "assistant", content: "nudged", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }
}

private func assertCodexSessionResolutionMetadata(
    _ resolutions: [AgentCLIKit.AgentInteractionResolution],
    expectedCount: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(resolutions.count, expectedCount, file: file, line: line)
    XCTAssertTrue(resolutions.allSatisfy { $0.metadata["approval_grant_kind"] == .string("session") }, file: file, line: line)
    XCTAssertTrue(resolutions.allSatisfy { $0.metadata["approval_provider_id"] == .string("codex") }, file: file, line: line)
    XCTAssertTrue(resolutions.allSatisfy { $0.metadata["approval_operation"] == .string("Bash") }, file: file, line: line)
}

/// First launch defers a tool approval and idles on stdin like the real CLI; the resumed launch only
/// answers once it receives the deferred-replay recovery user message over stdin.
private struct NudgeRecoveryAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let counter = AgentCLIKitLaunchCounter()
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        let launch = await counter.next()
        let script = launch == 1
            ? "printf 'approval\\ndeferred\\n'; cat > /dev/null"
            : """
            while IFS= read -r line; do
              case "$line" in
                *"Run that tool use again"*) printf 'message:nudged\\n'; exit 0 ;;
              esac
            done
            """
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", script],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if line == "approval" {
            return [.interaction(AgentCLIKit.AgentInteractionEvent(
                id: "tool-nudge",
                kind: .approval,
                prompt: "Bash",
                metadata: [
                    "session_id": .string("session-nudge"),
                    "tool_name": .string("Bash"),
                    "tool_input": .object(["command": .string("pwd")])
                ]
            ))]
        }
        if line == "deferred" {
            return [.usage(AgentCLIKit.AgentUsageEvent(
                model: nil,
                inputTokens: nil,
                outputTokens: nil,
                stopReason: "tool_deferred",
                metadata: ["stop_reason": .string("tool_deferred")]
            ))]
        }
        if line.hasPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: String(line.dropFirst("message:".count))))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .userMessage(let message):
            Data("\(message.text)\n".utf8)
        case .interactionResolution, .interrupt:
            Data()
        }
    }
}
