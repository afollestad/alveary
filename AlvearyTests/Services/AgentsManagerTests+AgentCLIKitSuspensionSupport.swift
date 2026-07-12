import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
func makeBlockingSuspensionFixture(
    adapter: any AgentCLIKit.AgentProviderAdapter,
    detectedPath: String,
    basePath: String,
    approvalStore: BlockingSuspensionApprovalStore
) -> BlockingSuspensionFixture {
    let sessionStore = AgentCLIKit.JSONFileAgentSessionStore(
        fileURL: suspensionTemporaryFileURL("agentclikit-sessions.json")
    )
    let configStore = AgentCLIKit.ClaudeConfigStore(fileURL: suspensionTemporaryFileURL("claude.json"))
    let runtime = AgentCLIKit.DefaultAgentRuntime(adapters: [adapter], sessionStore: sessionStore)
    let sessionManager = InMemorySessionManager()
    let services = AgentCLIKitHostServices(
        runtime: runtime,
        sessionStore: sessionStore,
        providerDetector: AgentCLIKit.AgentProviderDetector(),
        providerRegistry: AgentCLIKit.AgentProviderRegistry(definitions: [adapter.definition]),
        claudeConfigStore: configStore,
        claudeProviderSetup: AgentCLIKit.ClaudeProviderSetup(configStore: configStore),
        interactionStore: AgentCLIKit.InMemoryAgentInteractionStore(),
        approvalPolicyStore: AgentCLIKit.InMemoryAgentApprovalPolicyStore(),
        claudeApprovalPolicyStore: approvalStore,
        liveHookDecisionProvider: AgentCLIKitLiveHookDecisionProvider(),
        contextWindowCache: AgentCLIKit.JSONAgentModelContextWindowCache(
            fileURL: suspensionTemporaryFileURL("context.json")
        ),
        hostAdapter: AgentCLIKitHostAdapter()
    )
    let manager = DefaultAgentsManager(
        agentCLIKitServices: services,
        sessionManager: sessionManager,
        providerDetection: StubProviderDetectionService(resolvedPath: detectedPath),
        environmentBuilder: SuspensionFixedPathEnvironmentBuilder(path: basePath),
        providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
        settingsService: makeSettings(),
        keepAwakeService: RecordingKeepAwakeService(),
        notificationManager: StubNotificationManager()
    )
    return BlockingSuspensionFixture(manager: manager, sessionStore: sessionStore)
}

@MainActor
func assertSuspensionTeardownTombstonesArePreserved(
    manager: DefaultAgentsManager,
    conversationId: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let preservesClosingTombstone = await manager.closingConversationIds.contains(conversationId)
    let preservesPendingRemovalTombstone = await manager.pendingSessionRemovalIds.contains(conversationId)
    XCTAssertTrue(preservesClosingTombstone, file: file, line: line)
    XCTAssertTrue(preservesPendingRemovalTombstone, file: file, line: line)
}

func seedBlockingSuspensionSession(
    fixture: BlockingSuspensionFixture,
    runtimeConversationId: AgentCLIKit.AgentConversationID,
    workingDirectory: URL
) async throws {
    try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
        conversationId: runtimeConversationId,
        providerId: .claude,
        providerSessionId: "provider-session",
        workingDirectory: workingDirectory,
        generation: 1
    ))
}

@MainActor
func waitForSuspensionGate(_ gate: SuspensionAsyncGate, description: String) async throws {
    try await waitUntil(description) {
        await gate.hasEntered
    }
}

struct BlockingSuspensionFixture {
    let manager: DefaultAgentsManager
    let sessionStore: AgentCLIKit.JSONFileAgentSessionStore
}

struct SuspensionFixedPathEnvironmentBuilder: AgentEnvironmentBuilder {
    let path: String

    func buildEnvironment(providerEnv: [String: String]?) -> [String: String] {
        var environment = ["HOME": NSHomeDirectory(), "PATH": path]
        for (key, value) in providerEnv ?? [:] {
            environment[key] = value
        }
        return environment
    }
}

struct BlockingSuspensionAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let executableName: String
    let terminationGate: SuspensionAsyncGate
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

    func processDidTerminate(processToken: UUID) async {
        await terminationGate.enterAndWait()
    }
}

actor BlockingSuspensionApprovalStore:
    AgentCLIKit.ClaudeApprovalPolicyStoring,
    AgentCLIKit.ClaudeTransientDecisionStoring {
    private let base = AgentCLIKit.ClaudeApprovalPolicyStore()
    private let removalGate: SuspensionAsyncGate

    init(removalGate: SuspensionAsyncGate) {
        self.removalGate = removalGate
    }

    func approveForSession(operation: String) async {
        await base.approveForSession(operation: operation)
    }

    func approveForSession(operation: String, input: AgentCLIKit.JSONValue) async {
        await base.approveForSession(operation: operation, input: input)
    }

    func isSessionApproved(operation: String) async -> Bool {
        await base.isSessionApproved(operation: operation)
    }

    func isSessionApproved(operation: String, input: AgentCLIKit.JSONValue) async -> Bool {
        await base.isSessionApproved(operation: operation, input: input)
    }

    func recordSessionApproval(
        _ grant: AgentCLIKit.AgentSessionApprovalGrant
    ) async -> AgentCLIKit.AgentSessionApprovalRecordResult {
        await base.recordSessionApproval(grant)
    }

    func discardSessionApproval(_ grant: AgentCLIKit.AgentSessionApprovalGrant) async {
        await base.discardSessionApproval(grant)
    }

    func allowsSessionApproval(_ request: AgentCLIKit.AgentSessionApprovalRequest) async -> Bool {
        await base.allowsSessionApproval(request)
    }

    func removeSessionApprovals(
        providerId: AgentCLIKit.AgentProviderID,
        conversationId: AgentCLIKit.AgentConversationID,
        sessionId: AgentCLIKit.AgentSessionID
    ) async {
        await removalGate.enterAndWait()
        await base.removeSessionApprovals(
            providerId: providerId,
            conversationId: conversationId,
            sessionId: sessionId
        )
    }

    func approveBatch(_ ids: [AgentCLIKit.AgentInteractionID]) async {
        await base.approveBatch(ids)
    }

    func consumeTransientApproval(id: AgentCLIKit.AgentInteractionID) async -> Bool {
        await base.consumeTransientApproval(id: id)
    }

    func recordTransientDecision(
        _ decision: AgentCLIKit.ClaudeHookDecision,
        id: AgentCLIKit.AgentInteractionID
    ) async {
        await base.recordTransientDecision(decision, id: id)
    }

    func consumeTransientDecision(
        id: AgentCLIKit.AgentInteractionID
    ) async -> AgentCLIKit.ClaudeHookDecision? {
        await base.consumeTransientDecision(id: id)
    }

    func discardTransientDecision(id: AgentCLIKit.AgentInteractionID) async {
        await base.discardTransientDecision(id: id)
    }

    func recordTransientDecision(
        _ decision: AgentCLIKit.ClaudeHookDecision,
        for key: AgentCLIKit.ClaudeTransientDecisionKey
    ) async {
        await base.recordTransientDecision(decision, for: key)
    }

    func consumeTransientDecision(
        for key: AgentCLIKit.ClaudeTransientDecisionKey
    ) async -> AgentCLIKit.ClaudeHookDecision? {
        await base.consumeTransientDecision(for: key)
    }

    func discardTransientDecision(for key: AgentCLIKit.ClaudeTransientDecisionKey) async {
        await base.discardTransientDecision(for: key)
    }
}

actor SuspensionAsyncGate {
    private var isOpen = false
    private(set) var hasEntered = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        hasEntered = true
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func suspensionTemporaryFileURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name)
}
