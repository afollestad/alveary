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

    func testAgentCLIKitProviderSessionEnvelopeRecordsDurableBindingOnce() async throws {
        let executable = try makeScript(named: "codex-binding-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let bindingStore = RecordingProviderSessionBindingStore()
        let fixture = makeAgentCLIKitFixture(
            adapter: ProviderPathCLIKitAdapter(
                providerId: .codex,
                displayName: "Codex",
                executableName: executable.lastPathComponent,
                providerSessionId: "codex-thread"
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            providerSessionBindingStore: bindingStore
        )
        let conversationId = "agentclikit-codex-binding"
        let workingDirectory = executable.deletingLastPathComponent().path

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(
                providerId: "codex",
                workingDirectory: workingDirectory
            )
        )

        let expectedBinding = ProviderSessionBinding(
            conversationID: conversationId,
            providerID: "codex",
            providerSessionID: "codex-thread",
            workingDirectory: workingDirectory
        )
        try await waitUntil("expected AgentCLIKit provider session binding to be recorded once") {
            await bindingStore.recordedBindings == [expectedBinding]
        }

        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitProviderSessionMetadataUpdatesSessionBinding() async throws {
        let executable = try makeScript(named: "metadata-session-agent", body: "sleep 5\n")
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
        let conversationId = "agentclikit-session-metadata"
        let workingDirectory = executable.deletingLastPathComponent().path
        _ = await fixture.sessionManager.createEntry(
            conversationId: conversationId,
            cwd: workingDirectory,
            providerId: "codex"
        )

        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(providerId: "codex", workingDirectory: workingDirectory)
        )
        let maybeSubscription = await awaitedSubscription(
            fixture.manager,
            conversationId: conversationId,
            afterIndex: 0
        )
        let subscription = try XCTUnwrap(maybeSubscription)
        await fixture.manager.handleStreamEvent(
            ConversationEvent.providerSessionMetadataChanged(sessionId: "codex-thread", name: "Generated"),
            conversationId: conversationId,
            generation: subscription.generation,
            providerId: "codex"
        )

        try await waitUntil("expected metadata session id to update session binding") {
            await fixture.sessionManager.sessionId(for: conversationId) == "codex-thread"
        }
        await fixture.manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitProviderSessionMetadataDoesNotTriggerNotification() async {
        let fixture = makeAgentCLIKitFixture(
            adapter: ProviderPathCLIKitAdapter(
                providerId: .codex,
                displayName: "Codex",
                executableName: "codex"
            ),
            detectedPath: "/usr/bin/codex",
            basePath: "/usr/bin:/bin"
        )

        let canTriggerNotification = await fixture.manager.canTriggerNotification(
            .providerSessionMetadataChanged(sessionId: "codex-thread", name: "Generated")
        )

        XCTAssertFalse(canTriggerNotification)
    }

    func testClaudeApprovalStoreAdapterIgnoresNonClaudeSessionRemoval() async {
        let persistenceStore = RecordingClaudeApprovalPersistenceStore()
        let approvalStore = AgentCLIKitClaudeApprovalStoreAdapter(approvalPersistenceStore: persistenceStore)

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

        let removals = await persistenceStore.removedSessionApprovalIDs()
        XCTAssertEqual(removals.count, 1)
        XCTAssertEqual(removals.first?.conversationId, "conversation-1")
        XCTAssertEqual(removals.first?.sessionId, "claude-session")
    }

    func testAgentCLIKitSessionRecordRemovalClearsClaudeSessionApprovals() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ModelEchoingAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let conversationId = AgentCLIKit.AgentConversationID(rawValue: "conversation-approval-cleanup")
        let approvalRequest = AgentCLIKit.AgentSessionApprovalRequest(
            providerId: .claude,
            conversationId: conversationId,
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("pwd")])
        )
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: conversationId,
            providerId: .claude,
            providerSessionId: "session-1",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            generation: 1
        ))
        _ = await fixture.approvalStore.recordSessionApproval(AgentCLIKit.AgentSessionApprovalGrant(
            providerId: .claude,
            conversationId: conversationId,
            sessionId: "session-1",
            matchKind: .bashExact,
            matchValue: "pwd"
        ))

        try await fixture.manager.removeAgentCLIKitSessionRecord(
            conversationId: conversationId,
            activeProviderId: .claude,
            services: fixture.services
        )

        let remainingRecord = try await fixture.sessionStore.record(conversationId: conversationId, providerId: .claude)
        let stillApproved = await fixture.approvalStore.allowsSessionApproval(approvalRequest)
        XCTAssertNil(remainingRecord)
        XCTAssertFalse(stillApproved)
    }
}

private struct RemovedSessionApprovalID: Equatable {
    let conversationId: String
    let sessionId: String
}

private actor RecordingClaudeApprovalPersistenceStore: ClaudeApprovalPersistenceStore {
    private var removals: [RemovedSessionApprovalID] = []

    func recordSessionApproval(_ approval: Alveary.AgentSessionApprovalGrant) async -> Alveary.SessionApprovalRecordResult {
        Alveary.SessionApprovalRecordResult(isEffective: false, wasInserted: false)
    }

    func discardSessionApproval(_ approval: Alveary.AgentSessionApprovalGrant) async {}

    func allowsSessionApproval(
        providerId: String,
        conversationId: String,
        sessionId: String,
        toolName: String,
        toolInput: String
    ) async -> Bool {
        false
    }

    func toolApprovalSelection(providerId: String, conversationId: String, sessionId: String) async -> ToolApprovalSelection? {
        nil
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async {}

    func removeSessionApprovals(conversationId: String, sessionId: String) async {
        removals.append(RemovedSessionApprovalID(conversationId: conversationId, sessionId: sessionId))
    }

    func removedSessionApprovalIDs() -> [RemovedSessionApprovalID] {
        removals
    }
}

private struct ProviderPathCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition: AgentCLIKit.AgentProviderDefinition
    let executableName: String
    let providerSessionId: AgentCLIKit.AgentSessionID?

    init(
        providerId: AgentCLIKit.AgentProviderID,
        displayName: String,
        executableName: String,
        providerSessionId: AgentCLIKit.AgentSessionID? = nil
    ) {
        self.definition = AgentCLIKit.AgentProviderDefinition(
            id: providerId,
            displayName: displayName,
            executableNames: [executableName]
        )
        self.executableName = executableName
        self.providerSessionId = providerSessionId
    }

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/usr/bin/env",
            arguments: [executableName],
            providerSessionId: providerSessionId,
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

private actor RecordingProviderSessionBindingStore: ProviderSessionBindingStore {
    private var bindings: [ProviderSessionBinding] = []

    var recordedBindings: [ProviderSessionBinding] {
        bindings
    }

    func record(_ binding: ProviderSessionBinding) async {
        bindings.append(binding)
    }
}
