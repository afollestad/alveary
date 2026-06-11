import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension AgentsManagerTests {
    func testAgentCLIKitCancelledButRunningRuntimeRequiresRespawnForOutbound() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: CancellationRaceAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-cancelled-running-readiness"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }

        await manager.cancelTurn(conversationId: conversationId)

        try await waitUntil("expected cancelled lifecycle while process is still alive") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return status.state == .cancelled && status.isProcessRunning
        }

        let readiness = await manager.outboundReadiness(conversationId: conversationId)
        XCTAssertEqual(readiness, .respawnRequired)
        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        try await manager.sendMessage("after cancel", conversationId: conversationId)

        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitPendingInteractionBlocksOutboundReadiness() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-pending-interaction-readiness"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))

        try await waitUntil("expected AgentCLIKit runtime to wait on approval") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.waitingState == .approval
        }

        let readiness = await manager.outboundReadiness(conversationId: conversationId)
        XCTAssertEqual(readiness, .blocked(reason: "Approve or deny the pending tool use before sending another message"))

        await manager.kill(conversationId: conversationId)
    }
}

private struct CancellationRaceAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"]
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                """
                trap '' TERM
                while IFS= read -r line; do
                  printf 'message:%s\\n' "$line"
                done
                """
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        if case let .userMessage(message) = input {
            return Data((message.text + "\n").utf8)
        }
        return Data()
    }
}
