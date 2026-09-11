import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitRestoredDeferredApprovalResumesWithoutTrackedProcess() async throws {
        let conversationId = "agentclikit-restored-deferred-approval"
        let fixture = try await resolveRestoredDeferredApproval(conversationId: conversationId)
        await assertResumedApprovalIsWorking(fixture, conversationId: conversationId)

        await fixture.manager.cancelTurn(conversationId: conversationId)
        try await waitUntil("expected cancelled deferred approval to become idle") {
            let status = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))
            guard status?.state == .cancelled, status?.isTurnActive == false else {
                return false
            }
            return await fixture.manager.refreshStatus(conversationId: conversationId) == .idle
        }
        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitCompletedDeferredApprovalClearsActivityWhileProcessRemainsRunning() async throws {
        let conversationId = "agentclikit-restored-deferred-completion"
        let fixture = try await resolveRestoredDeferredApproval(conversationId: conversationId)
        await assertResumedApprovalIsWorking(fixture, conversationId: conversationId)
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await fixture.runtime.send(.userMessage(AgentCLIKit.AgentMessageInput(text: "finish")), conversationId: runtimeConversationId)
        try await waitUntil("expected completed deferred approval to become idle") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId),
                  status.isProcessRunning,
                  !status.isTurnActive else {
                return false
            }
            return await fixture.manager.refreshStatus(conversationId: conversationId) == .idle
        }
        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitRestoredDeferredPromptDenialRemainsIdle() async throws {
        let conversationId = "agentclikit-restored-deferred-denial"
        let fixture = try await resolveRestoredDeferredApproval(conversationId: conversationId, decision: .deny)
        let status = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))
        let refreshedStatus = await fixture.manager.refreshStatus(conversationId: conversationId)

        XCTAssertEqual(status?.isProcessRunning, true)
        XCTAssertEqual(status?.isTurnActive, false)
        XCTAssertEqual(refreshedStatus, .idle)
        XCTAssertFalse(fixture.manager.conversationState(for: conversationId).turnState.isActive)
        await fixture.manager.kill(conversationId: conversationId)
    }

    func assertResumedApprovalIsWorking(
        _ fixture: AgentCLIKitManagerFixture,
        conversationId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let status = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))
        let refreshedStatus = await fixture.manager.refreshStatus(conversationId: conversationId)
        let state = fixture.manager.conversationState(for: conversationId)
        let activityVisibility = await fixture.manager.eventBuffers[conversationId]?.currentTurnActivityVisibility
        XCTAssertEqual(status?.isProcessRunning, true, file: file, line: line)
        XCTAssertEqual(status?.isTurnActive, true, file: file, line: line)
        XCTAssertEqual(refreshedStatus, .busy, file: file, line: line)
        XCTAssertTrue(state.turnState.isActive, file: file, line: line)
        XCTAssertEqual(activityVisibility, .visible, file: file, line: line)
    }

    /// An app-native answer skips the recovery user message that could otherwise hide an idle resumed runtime.
    private func resolveRestoredDeferredApproval(
        conversationId: String,
        decision: ClaudeToolApprovalDecision = .allow
    ) async throws -> AgentCLIKitManagerFixture {
        let fixture = makeAgentCLIKitFixture(
            adapter: RestoredApprovalCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let runtimeStatus = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))
        XCTAssertNil(runtimeStatus)
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
                decision: decision,
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
        return fixture
    }
}

struct RestoredApprovalCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        let script = """
        printf 'message:restored-resumed\\n'
        while IFS= read -r line; do
          if [ "$line" = "finish" ]; then
            printf 'usage:end_turn\\n'
          fi
        done
        """
        return AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", script],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        if let stopReason = line.removingPrefix("usage:") {
            return [.usage(AgentCLIKit.AgentUsageEvent(
                model: nil,
                inputTokens: nil,
                outputTokens: nil,
                stopReason: stopReason
            ))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        if case let .userMessage(message) = input {
            return Data("\(message.text)\n".utf8)
        }
        return Data()
    }
}
