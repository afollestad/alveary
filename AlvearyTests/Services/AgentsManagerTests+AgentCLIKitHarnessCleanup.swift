import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitKillRemovesActiveHarnessSessionRecord() async throws {
        let executable = try makeScript(named: "codex-idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let fixture = makeAgentCLIKitFixture(
            adapter: HarnessPathCLIKitAdapter(
                harnessId: .codex,
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
            harnessId: .codex,
            harnessSessionId: "codex-session",
            workingDirectory: executable.deletingLastPathComponent(),
            generation: 1
        ))

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(
                harnessId: "codex",
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
                harnessId: .codex
            ) == nil
        }
    }

    func testAgentCLIKitHarnessSessionEnvelopeRecordsDurableBindingOnce() async throws {
        let executable = try makeScript(named: "codex-binding-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let bindingStore = RecordingHarnessSessionBindingStore()
        let fixture = makeAgentCLIKitFixture(
            adapter: HarnessPathCLIKitAdapter(
                harnessId: .codex,
                displayName: "Codex",
                executableName: executable.lastPathComponent,
                harnessSessionId: "codex-thread"
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            harnessSessionBindingStore: bindingStore
        )
        let conversationId = "agentclikit-codex-binding"
        let workingDirectory = executable.deletingLastPathComponent().path

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(
                harnessId: "codex",
                workingDirectory: workingDirectory
            )
        )

        let expectedBinding = HarnessSessionBinding(
            conversationID: conversationId,
            harnessID: "codex",
            harnessSessionID: "codex-thread",
            workingDirectory: workingDirectory
        )
        try await waitUntil("expected AgentCLIKit harness session binding to be recorded once") {
            await bindingStore.recordedBindings == [expectedBinding]
        }

        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitHarnessSessionMetadataUpdatesSessionBinding() async throws {
        let executable = try makeScript(named: "metadata-session-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let fixture = makeAgentCLIKitFixture(
            adapter: HarnessPathCLIKitAdapter(
                harnessId: .codex,
                displayName: "Codex",
                executableName: executable.lastPathComponent
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        )
        let conversationId = "agentclikit-session-metadata"
        let workingDirectory = executable.deletingLastPathComponent().path
        _ = await fixture.sessionManager.createEntry(
            conversationId: conversationId,
            cwd: workingDirectory,
            harnessId: "codex"
        )

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(harnessId: "codex", workingDirectory: workingDirectory)
        )
        let maybeSubscription = await awaitedSubscription(
            fixture.manager,
            conversationId: conversationId,
            afterIndex: 0
        )
        let subscription = try XCTUnwrap(maybeSubscription)
        await fixture.manager.handleStreamEvent(
            ConversationEvent.harnessSessionMetadataChanged(sessionId: "codex-thread", name: "Generated", preview: nil),
            conversationId: conversationId,
            generation: subscription.generation,
            harnessId: "codex"
        )

        try await waitUntil("expected metadata session id to update session binding") {
            await fixture.sessionManager.sessionId(for: conversationId) == "codex-thread"
        }
        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitHarnessSessionMetadataDoesNotTriggerNotification() async {
        let fixture = makeAgentCLIKitFixture(
            adapter: HarnessPathCLIKitAdapter(
                harnessId: .codex,
                displayName: "Codex",
                executableName: "codex"
            ),
            detectedPath: "/usr/bin/codex",
            basePath: "/usr/bin:/bin"
        )

        let canTriggerNotification = await fixture.manager.canTriggerNotification(
            .harnessSessionMetadataChanged(sessionId: "codex-thread", name: "Generated", preview: "Preview")
        )

        XCTAssertFalse(canTriggerNotification)
    }

    func testClaudeApprovalStoreAdapterRemovesHarnessScopedSessionApprovals() async {
        let persistenceStore = RecordingClaudeApprovalPersistenceStore()
        let approvalStore = AgentCLIKitClaudeApprovalStoreAdapter(approvalPersistenceStore: persistenceStore)

        await approvalStore.removeSessionApprovals(
            harnessId: .codex,
            conversationId: "conversation-1",
            sessionId: "shared-session"
        )
        await approvalStore.removeSessionApprovals(
            harnessId: .claude,
            conversationId: "conversation-1",
            sessionId: "claude-session"
        )

        let removals = await persistenceStore.removedSessionApprovalIDs()
        XCTAssertEqual(removals.count, 2)
        XCTAssertEqual(removals.first?.conversationId, "conversation-1")
        XCTAssertEqual(removals.first?.harnessId, "codex")
        XCTAssertEqual(removals.first?.sessionId, "shared-session")
        XCTAssertEqual(removals.last?.harnessId, "claude")
        XCTAssertEqual(removals.last?.sessionId, "claude-session")
    }

    func testAgentCLIKitSessionRecordRemovalClearsClaudeSessionApprovals() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ModelEchoingAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let conversationId = AgentCLIKit.AgentConversationID(rawValue: "conversation-approval-cleanup")
        let approvalRequest = AgentCLIKit.AgentSessionApprovalRequest(
            harnessId: .claude,
            conversationId: conversationId,
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("pwd")])
        )
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: conversationId,
            harnessId: .claude,
            harnessSessionId: "session-1",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            generation: 1
        ))
        _ = await fixture.approvalStore.recordSessionApproval(AgentCLIKit.AgentSessionApprovalGrant(
            harnessId: .claude,
            conversationId: conversationId,
            sessionId: "session-1",
            matchKind: .bashExact,
            matchValue: "pwd"
        ))

        try await fixture.manager.removeAgentCLIKitSessionRecord(
            conversationId: conversationId,
            activeHarnessId: .claude,
            services: fixture.services
        )

        let remainingRecord = try await fixture.sessionStore.record(conversationId: conversationId, harnessId: .claude)
        let stillApproved = await fixture.approvalStore.allowsSessionApproval(approvalRequest)
        XCTAssertNil(remainingRecord)
        XCTAssertFalse(stillApproved)
    }
}

private struct RemovedSessionApprovalID: Equatable {
    let harnessId: String
    let conversationId: String
    let sessionId: String
}

private actor RecordingClaudeApprovalPersistenceStore: ClaudeApprovalPersistenceStore {
    private var removals: [RemovedSessionApprovalID] = []

    func recordSessionApproval(_ approval: Alveary.AgentSessionApprovalGrant) async -> Alveary.SessionApprovalRecordResult {
        Alveary.SessionApprovalRecordResult(isEffective: false, wasInserted: false)
    }

    func discardSessionApproval(_ approval: Alveary.AgentSessionApprovalGrant) async {}

    func allowsSessionApproval(matching candidates: [Alveary.AgentSessionApprovalGrant]) async -> Bool {
        false
    }

    func toolApprovalSelection(harnessId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection? {
        nil
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        harnessId: String,
        conversationId: String,
        sessionId: String
    ) async {}

    func removeSessionApprovals(harnessId: String, conversationId: String, sessionId: String) async {
        removals.append(RemovedSessionApprovalID(harnessId: harnessId, conversationId: conversationId, sessionId: sessionId))
    }

    func removedSessionApprovalIDs() -> [RemovedSessionApprovalID] {
        removals
    }
}

private struct HarnessPathCLIKitAdapter: AgentCLIKit.AgentHarnessAdapter {
    let definition: AgentCLIKit.AgentHarnessDefinition
    let executableName: String
    let harnessSessionId: AgentCLIKit.AgentSessionID?

    init(
        harnessId: AgentCLIKit.AgentHarnessID,
        displayName: String,
        executableName: String,
        harnessSessionId: AgentCLIKit.AgentSessionID? = nil
    ) {
        self.definition = AgentCLIKit.AgentHarnessDefinition(
            id: harnessId,
            displayName: displayName,
            executableNames: [executableName]
        )
        self.executableName = executableName
        self.harnessSessionId = harnessSessionId
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/usr/bin/env",
            arguments: [executableName],
            harnessSessionId: harnessSessionId,
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

private actor RecordingHarnessSessionBindingStore: HarnessSessionBindingStore {
    private var bindings: [HarnessSessionBinding] = []

    var recordedBindings: [HarnessSessionBinding] {
        bindings
    }

    func record(_ binding: HarnessSessionBinding) async {
        bindings.append(binding)
    }
}
