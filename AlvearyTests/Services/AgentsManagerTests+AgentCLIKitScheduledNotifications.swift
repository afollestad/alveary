import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAutomatedScheduledTurnDefersOnlyTerminalNotifications() async throws {
        let executable = try makeScript(named: "slow-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let notifications = StubNotificationManager()
        let fixture = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            notificationManager: notifications
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-automated-scheduled-notification"

        try await manager.spawn(
            id: conversationId,
            config: scheduledSpawnConfig(workingDirectory: executable.deletingLastPathComponent().path)
        )
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)
        await manager.markCurrentTurnActivityVisibility(.visible, conversationId: conversationId)
        let questionEvent = ConversationEvent.notification(type: "idle_prompt", message: "Which target?")
        let approvalEvent = scheduledApprovalEvent()

        await manager.handleStreamEvent(
            questionEvent,
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )
        await manager.handleStreamEvent(
            approvalEvent,
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )
        await manager.handleStreamEvent(
            scheduledTerminalSuccessTokens(),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )

        XCTAssertEqual(notifications.handledEvents.map(\.event), [questionEvent, approvalEvent])
        await manager.kill(conversationId: conversationId)
    }

    private func scheduledSpawnConfig(workingDirectory: String) -> Alveary.AgentSpawnConfig {
        Alveary.AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: workingDirectory,
            permissionMode: nil,
            model: nil,
            effort: nil,
            initialPrompt: nil,
            isAutomatedScheduledTurn: true
        )
    }

    private func scheduledApprovalEvent() -> ConversationEvent {
        .toolApprovalRequested(ToolApprovalRequest(
            sessionId: "scheduled-session",
            toolUseId: "scheduled-tool",
            toolName: "Bash",
            toolInput: #"{"command":"swift test"}"#
        ))
    }

    private func scheduledTerminalSuccessTokens() -> ConversationEvent {
        .tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: [],
            isTerminal: true
        )
    }
}
