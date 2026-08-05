import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitFailedStartFreshSessionRestoresExistingSubscription() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: FailedReplacementAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-failed-fresh-session"
        let seededSession = try await seedAgentCLIKitSessionApproval(
            fixture,
            conversationId: conversationId
        )

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: "/tmp")
        )
        do {
            try await manager.startFreshSession(
                conversationId: conversationId,
                config: spawnConfig(workingDirectory: "/tmp")
            )
            XCTFail("Expected AgentCLIKit fresh session replacement to fail.")
        } catch {
            // Expected: the replacement launch fails while AgentCLIKit keeps the previous process alive.
        }
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let event = try await nextEvent(
            from: subscription.stream,
            description: "old AgentCLIKit event after failed fresh session"
        )
        let runtimeStatus = await fixture.runtime.status(conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId))
        let restoredRecord = try await fixture.sessionStore.record(
            conversationId: seededSession.runtimeConversationId,
            providerId: .claude
        )
        let stillAllowsApproval = await fixture.approvalStore.allowsSessionApproval(seededSession.approvalRequest)

        XCTAssertEqual(event, .message(role: "assistant", content: "old-after-failed-reconfigure", parentToolUseId: nil))
        XCTAssertEqual(runtimeStatus?.state, .running)
        XCTAssertEqual(restoredRecord?.providerSessionId, "session-1")
        XCTAssertTrue(stillAllowsApproval)
        XCTAssertEqual(manager.status(for: conversationId), .error)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitStartFreshSessionRemovesPreviousSessionApprovals() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ModelEchoingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let conversationId = "agentclikit-fresh-session-approvals"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        let approvalRequest = AgentCLIKit.AgentSessionApprovalRequest(
            providerId: .claude,
            conversationId: runtimeConversationId,
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("pwd")])
        )
        let approvalGrant = try XCTUnwrap(approvalRequest.sessionApprovalGrant(for: .exact))
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: runtimeConversationId,
            providerId: .claude,
            providerSessionId: "session-1",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            generation: 1
        ))
        _ = await fixture.approvalStore.recordSessionApproval(approvalGrant)

        try await fixture.manager.startFreshSession(
            conversationId: conversationId,
            config: spawnConfig(workingDirectory: "/tmp", model: "fresh")
        )
        let stillAllowsApproval = await fixture.approvalStore.allowsSessionApproval(approvalRequest)
        let previousRecord = try await fixture.sessionStore.record(
            conversationId: runtimeConversationId,
            providerId: .claude
        )

        XCTAssertFalse(stillAllowsApproval)
        XCTAssertNil(previousRecord)
        await fixture.manager.kill(conversationId: conversationId)
    }

    /// A handoff spawns fresh, so the runtime never sees the previous session replaced; the manager itself must
    /// archive it (and the lineage on its record) with the provider before removing the record.
    func testAgentCLIKitStartFreshSessionArchivesPreviousProviderSession() async throws {
        let adapter = ArchivingModelEchoingAgentCLIKitAdapter()
        let fixture = makeAgentCLIKitFixture(
            adapter: adapter,
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let conversationId = "agentclikit-fresh-session-archive"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: runtimeConversationId,
            providerId: .claude,
            providerSessionId: "session-1",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            generation: 1
        ))

        try await fixture.manager.startFreshSession(
            conversationId: conversationId,
            config: spawnConfig(workingDirectory: "/tmp", model: "fresh")
        )
        let archivedSessionIds = await adapter.archiveRecorder.archivedSessionIds()
        let previousRecord = try await fixture.sessionStore.record(
            conversationId: runtimeConversationId,
            providerId: .claude
        )

        XCTAssertEqual(archivedSessionIds, ["session-1"])
        XCTAssertNotEqual(previousRecord?.providerSessionId, "session-1")
        await fixture.manager.kill(conversationId: conversationId)
    }

    private func seedAgentCLIKitSessionApproval(
        _ fixture: AgentCLIKitManagerFixture,
        conversationId: String
    ) async throws -> (
        runtimeConversationId: AgentCLIKit.AgentConversationID,
        approvalRequest: AgentCLIKit.AgentSessionApprovalRequest
    ) {
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        let approvalRequest = AgentCLIKit.AgentSessionApprovalRequest(
            providerId: .claude,
            conversationId: runtimeConversationId,
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("pwd")])
        )
        let approvalGrant = try XCTUnwrap(approvalRequest.sessionApprovalGrant(for: .exact))
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: runtimeConversationId,
            providerId: .claude,
            providerSessionId: "session-1",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            generation: 1
        ))
        _ = await fixture.approvalStore.recordSessionApproval(approvalGrant)
        return (runtimeConversationId, approvalRequest)
    }
}

/// Echoes the launch model like `ModelEchoingAgentCLIKitAdapter`, but reports session-archiving support and records
/// which sessions the host archives, so handoff cleanup is observable.
private struct ArchivingModelEchoingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let archiveRecorder = SessionArchiveRecorder()
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"],
        capabilities: AgentCLIKit.AgentProviderCapabilities(supportsSessionArchiving: true)
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "printf 'message:%s\\n' \"$1\"",
                "agent",
                spawnConfig.model ?? "default"
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
        Data()
    }

    func archiveSession(_ record: AgentCLIKit.AgentSessionRecord) async throws {
        await archiveRecorder.record(record.providerSessionId)
    }
}

private actor SessionArchiveRecorder {
    private var sessionIds: [AgentCLIKit.AgentSessionID] = []

    func record(_ sessionId: AgentCLIKit.AgentSessionID) {
        sessionIds.append(sessionId)
    }

    func archivedSessionIds() -> [AgentCLIKit.AgentSessionID] {
        sessionIds
    }
}
