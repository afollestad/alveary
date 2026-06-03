import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitKillRemovesActiveProviderSessionRecord() async throws {
        let executable = try makeScript(named: "codex-idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let fixture = makeAgentCLIKitFixture(
            adapter: ProviderPathCLIKitAdapter(
                providerId: .codex,
                displayName: "Codex",
                executableName: executable.lastPathComponent
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        )
        let conversationId = "agentclikit-codex-session-cleanup"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: runtimeConversationId,
            providerId: .codex,
            providerSessionId: "codex-session",
            workingDirectory: executable.deletingLastPathComponent(),
            generation: 1
        ))

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(
                providerId: "codex",
                workingDirectory: executable.deletingLastPathComponent().path
            )
        )
        try await waitUntil("expected Codex AgentCLIKit runtime to be running") {
            await fixture.manager.isRunning(conversationId: conversationId)
        }

        await fixture.manager.kill(conversationId: conversationId)

        try await waitUntil("expected Codex AgentCLIKit session record removal") {
            try await fixture.sessionStore.record(
                conversationId: runtimeConversationId,
                providerId: .codex
            ) == nil
        }
    }

    func testClaudeApprovalStoreAdapterIgnoresNonClaudeSessionRemoval() async {
        let hookServer = StubClaudeHookServer(launchConfig: nil)
        let approvalStore = AgentCLIKitClaudeApprovalStoreAdapter(claudeHookServer: hookServer)

        await approvalStore.removeSessionApprovals(
            providerId: .codex,
            conversationId: "conversation-1",
            sessionId: "shared-session"
        )
        await approvalStore.removeSessionApprovals(
            providerId: .claude,
            conversationId: "conversation-1",
            sessionId: "claude-session"
        )

        let removals = await hookServer.removedSessionApprovalIDs()
        XCTAssertEqual(removals.count, 1)
        XCTAssertEqual(removals.first?.conversationId, "conversation-1")
        XCTAssertEqual(removals.first?.sessionId, "claude-session")
    }
}

private struct ProviderPathCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition: AgentCLIKit.AgentProviderDefinition
    let executableName: String

    init(providerId: AgentCLIKit.AgentProviderID, displayName: String, executableName: String) {
        self.definition = AgentCLIKit.AgentProviderDefinition(
            id: providerId,
            displayName: displayName,
            executableNames: [executableName]
        )
        self.executableName = executableName
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/usr/bin/env",
            arguments: [executableName],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}
