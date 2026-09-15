import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitSuppressesTrailingGenericTokenNotificationAfterHarnessError() async throws {
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
        let conversationId = "agentclikit-duplicate-error-notification"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markCurrentTurnActivityVisibility(.visible, conversationId: conversationId)
        await manager.handleStreamEvent(
            .error(message: "Selected model is unavailable."),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )
        await manager.handleStreamEvent(
            tokenError(stopReason: "stop_sequence"),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )

        let handled = try XCTUnwrap(notifications.handledEvents.first)
        XCTAssertEqual(notifications.handledEvents.count, 1)
        XCTAssertEqual(handled.conversationId, conversationId)
        XCTAssertEqual(handled.event, .error(message: "Selected model is unavailable."))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitDoesNotSuppressSpecificTokenNotificationAfterHarnessError() async throws {
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
        let conversationId = "agentclikit-specific-error-notification"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markCurrentTurnActivityVisibility(.visible, conversationId: conversationId)
        await manager.handleStreamEvent(
            .error(message: "Selected model is unavailable."),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )
        await manager.handleStreamEvent(
            tokenError(stopReason: "provider_model_unavailable"),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )

        XCTAssertEqual(notifications.handledEvents.count, 2)
        XCTAssertEqual(notifications.handledEvents.first?.event, .error(message: "Selected model is unavailable."))
        XCTAssertEqual(notifications.handledEvents.last?.conversationId, conversationId)
        XCTAssertEqual(notifications.handledEvents.last?.event, tokenError(stopReason: "provider_model_unavailable"))
        await manager.kill(conversationId: conversationId)
    }

    func testSteeredConversationDoesNotTriggerNotification() async {
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: "agent"),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        ).manager

        let canTriggerNotification = await manager.canTriggerNotification(.steeredConversation(inputID: "local-user-1"))
        XCTAssertFalse(canTriggerNotification)
    }

    func testHiddenTerminalActivityDoesNotTriggerNotification() async throws {
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
        let conversationId = "agentclikit-hidden-terminal-notification"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markCurrentTurnActivityVisibility(.hidden, conversationId: conversationId)
        await manager.handleStreamEvent(
            terminalSuccessTokens(),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )

        XCTAssertTrue(notifications.handledEvents.isEmpty)
        await manager.kill(conversationId: conversationId)
    }

    func testVisibleTerminalActivityStillNotifiesAfterVisibilityCleanup() async throws {
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
        let conversationId = "agentclikit-visible-terminal-notification"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markCurrentTurnActivityVisibility(.visible, conversationId: conversationId)
        await manager.handleStreamEvent(
            terminalSuccessTokens(),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )

        XCTAssertEqual(notifications.handledEvents.count, 1)
        XCTAssertEqual(notifications.handledEvents.first?.conversationId, conversationId)
        XCTAssertEqual(notifications.handledEvents.first?.event, terminalSuccessTokens())
        let currentVisibility = await manager.eventBuffers[conversationId]?.currentTurnActivityVisibility
        XCTAssertEqual(currentVisibility, .hidden)
        await manager.kill(conversationId: conversationId)
    }

    func testStatusDrivenTurnEndBeforeTerminalTokenStillNotifies() async throws {
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
        let conversationId = "agentclikit-status-first-terminal-notification"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.markCurrentTurnActivityVisibility(.visible, conversationId: conversationId)
        // Drive the status stream by hand so the turn-ended status lands before the terminal token.
        await manager.handleRuntimeTurnActiveStatus(
            runtimeStatus(conversationId: conversationId, isTurnActive: true),
            conversationId: conversationId
        )
        await manager.handleRuntimeTurnActiveStatus(
            runtimeStatus(conversationId: conversationId, isTurnActive: false),
            conversationId: conversationId
        )
        await manager.handleStreamEvent(
            terminalSuccessTokens(),
            conversationId: conversationId,
            generation: generation,
            harnessId: "claude"
        )

        XCTAssertEqual(notifications.handledEvents.count, 1)
        XCTAssertEqual(notifications.handledEvents.first?.conversationId, conversationId)
        XCTAssertEqual(notifications.handledEvents.first?.event, terminalSuccessTokens())
        await manager.kill(conversationId: conversationId)
    }

    func testOrdinaryPRReviewProposalNotifiesWhenTurnFinishes() async throws {
        for harnessId in [AgentCLIKit.AgentHarnessID.claude, .codex] {
            try await assertOrdinaryPRReviewProposalNotifies(harnessId: harnessId)
        }
    }

    func testOrdinaryPRReviewProposalNotifiesWhenStatusFinishesBeforeTokens() async throws {
        for harnessId in [AgentCLIKit.AgentHarnessID.claude, .codex] {
            try await assertOrdinaryPRReviewProposalNotifies(harnessId: harnessId, statusFinishesFirst: true)
        }
    }

    private func assertOrdinaryPRReviewProposalNotifies(
        harnessId: AgentCLIKit.AgentHarnessID,
        statusFinishesFirst: Bool = false
    ) async throws {
        let notifications = StubNotificationManager()
        let manager = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(harnessId: harnessId),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin",
            notificationManager: notifications
        ).manager
        let conversationId = "ordinary-review-\(harnessId.rawValue)"
        let events = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        defer { events.continuation.finish() }
        await manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: spawnConfig(harnessId: harnessId.rawValue, workingDirectory: "/tmp"),
            subscription: AgentCLIKit.AgentEventSubscription(generation: 1, events: events.stream),
            hasImmediateTurn: true,
            initialTurnActivityVisibility: .visible
        )
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)
        let receipt = harnessId == .claude
            ? #"{"status":"pending_confirmation","proposal_id":"proposal-1","repository":"owner/repo","number":1}"#
            : "Review proposal opened for confirmation."
        let proposalEvents: [ConversationEvent] = [
            .toolCall(
                id: "review-proposal",
                name: "mcp__alveary_host__propose_pr_review",
                input: #"{"url":"https://github.com/owner/repo/pull/1","event":"APPROVE"}"#,
                parentToolUseId: nil,
                callerAgent: nil
            ),
            .toolResult(id: "review-proposal", output: receipt, isError: false, parentToolUseId: nil, metadata: nil)
        ]
        for event in proposalEvents {
            await manager.handleStreamEvent(event, conversationId: conversationId, generation: generation, harnessId: harnessId.rawValue)
        }
        XCTAssertTrue(notifications.handledEvents.isEmpty, "Staging alone must not announce turn completion for \(harnessId.rawValue)")

        if statusFinishesFirst {
            for isTurnActive in [true, false] {
                await manager.handleRuntimeTurnActiveStatus(
                    runtimeStatus(conversationId: conversationId, isTurnActive: isTurnActive, harnessId: harnessId),
                    conversationId: conversationId
                )
            }
        }
        await manager.handleStreamEvent(
            terminalSuccessTokens(), conversationId: conversationId, generation: generation, harnessId: harnessId.rawValue
        )

        XCTAssertEqual(notifications.handledEvents.count, 1, harnessId.rawValue)
        XCTAssertEqual(notifications.handledEvents.first?.conversationId, conversationId)
        XCTAssertEqual(notifications.handledEvents.first?.event, terminalSuccessTokens())
    }

    private func runtimeStatus(
        conversationId: String,
        isTurnActive: Bool,
        harnessId: AgentCLIKit.AgentHarnessID = .claude
    ) -> AgentCLIKit.AgentRuntimeStatus {
        AgentCLIKit.AgentRuntimeStatus(
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
            harnessId: harnessId,
            generation: 1,
            state: .running,
            lastEventIndex: 1,
            harnessSessionId: nil,
            isTurnActive: isTurnActive
        )
    }

    private func tokenError(stopReason: String) -> ConversationEvent {
        .tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: true,
            stopReason: stopReason,
            durationMs: 10,
            costUsd: 0,
            permissionDenials: [],
            isTerminal: true
        )
    }

    private func terminalSuccessTokens() -> ConversationEvent {
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
