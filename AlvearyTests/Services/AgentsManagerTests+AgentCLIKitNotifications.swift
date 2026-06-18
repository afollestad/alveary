import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitSuppressesTrailingGenericTokenNotificationAfterProviderError() async throws {
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

        await manager.handleStreamEvent(
            .error(message: "Selected model is unavailable."),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )
        await manager.handleStreamEvent(
            tokenError(stopReason: "stop_sequence"),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )

        let handled = try XCTUnwrap(notifications.handledEvents.first)
        XCTAssertEqual(notifications.handledEvents.count, 1)
        XCTAssertEqual(handled.conversationId, conversationId)
        XCTAssertEqual(handled.event, .error(message: "Selected model is unavailable."))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitDoesNotSuppressSpecificTokenNotificationAfterProviderError() async throws {
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

        await manager.handleStreamEvent(
            .error(message: "Selected model is unavailable."),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )
        await manager.handleStreamEvent(
            tokenError(stopReason: "provider_model_unavailable"),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
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
}
