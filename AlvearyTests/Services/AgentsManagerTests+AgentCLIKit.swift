import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitRuntimeAddsDetectedExecutableDirectoryToPath() async throws {
        let executable = try makeScript(named: "path-agent", body: "printf 'message:path-ok\\n'\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-path"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let event = try await nextEvent(from: subscription.stream, description: "AgentCLIKit path launch event")

        XCTAssertEqual(event, .message(role: "assistant", content: "path-ok", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitToolApprovalResolutionUsesRuntimeResolution() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-approval"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AgentCLIKit approval event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }

        let didRecordSessionApproval = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        let maybeResolvedSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 1)
        let resolvedSubscription = try XCTUnwrap(maybeResolvedSubscription)
        let messageEvent = try await nextEvent(
            from: resolvedSubscription.stream,
            description: "AgentCLIKit approval resolution event"
        )

        XCTAssertFalse(didRecordSessionApproval)
        XCTAssertEqual(messageEvent, .message(role: "assistant", content: "resolved:approved", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitSessionApprovalRecordsInAgentCLIKitStore() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-session-approval"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AgentCLIKit session approval event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        let sessionApproval = try XCTUnwrap(approval.sessionApprovalGrant(
            conversationId: conversationId,
            providerId: "claude",
            scope: .exact
        ))

        let didRecordSessionApproval = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: sessionApproval,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        let allowsApproval = await fixture.approvalStore.allowsSessionApproval(AgentCLIKit.AgentSessionApprovalRequest(
            providerId: .claude,
            conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
            sessionId: "session-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("pwd")])
        ))

        XCTAssertTrue(didRecordSessionApproval)
        XCTAssertTrue(allowsApproval)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitApprovalStoreScopesTransientDecisionsBySession() async {
        let approvalStore = AgentCLIKitClaudeApprovalStoreAdapter(claudeHookServer: DisabledClaudeHookServer())
        let scopedKey = AgentCLIKit.ClaudeTransientDecisionKey(sessionId: "session-1", interactionId: "tool-1")

        await approvalStore.recordTransientDecision(.deny(reason: "No"), for: scopedKey)
        let wrongSessionDecision = await approvalStore.consumeTransientDecision(
            for: AgentCLIKit.ClaudeTransientDecisionKey(sessionId: "session-2", interactionId: "tool-1")
        )
        let matchingSessionDecision = await approvalStore.consumeTransientDecision(for: scopedKey)

        XCTAssertNil(wrongSessionDecision)
        XCTAssertEqual(matchingSessionDecision?.approval, .deny)
        XCTAssertEqual(matchingSessionDecision?.reason, "No")
    }

    func testAgentCLIKitFallbackApprovalRecordsTransientDecisionAndRespawns() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DeferredThenMessageAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fallback-approval"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: "/tmp"))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)
        let approvalEvent = try await nextEvent(from: subscription.stream, description: "AgentCLIKit fallback approval event")
        guard case let .toolApprovalRequested(approval) = approvalEvent else {
            return XCTFail("Expected tool approval request, got \(approvalEvent)")
        }
        try await waitUntil("expected fallback approval to wait for user") {
            manager.status(for: conversationId) == .waitingForUser
        }

        let didRecordSessionApproval = try await manager.resolveToolApproval(AgentToolApprovalResolutionRequest(
            conversationId: conversationId,
            approval: approval,
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            additionalApprovals: [],
            sessionApproval: nil,
            config: spawnConfig(workingDirectory: "/tmp")
        ))
        var resumedSubscription: Alveary.AgentEventSubscription?
        try await waitUntil("expected AgentCLIKit fallback approval to install resumed buffer") {
            let candidate = await self.awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
            resumedSubscription = candidate?.generation == subscription.generation ? nil : candidate
            return resumedSubscription != nil
        }
        let resolvedSubscription = try XCTUnwrap(resumedSubscription)
        let messageEvent = try await nextEvent(
            from: resolvedSubscription.stream,
            description: "AgentCLIKit fallback approval resumed event"
        )

        XCTAssertFalse(didRecordSessionApproval)
        XCTAssertEqual(messageEvent, .message(role: "assistant", content: "resumed", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitReconfigureDoesNotReplayRetainedRuntimeEvents() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DelayedReconfigureAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-reconfigure-replay"

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: "/tmp")
        )
        let maybeFirstSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let firstSubscription = try XCTUnwrap(maybeFirstSubscription)
        let firstEvent = try await nextEvent(from: firstSubscription.stream, description: "first AgentCLIKit launch event")
        await manager.markPersisted(conversationId: conversationId, generation: firstSubscription.generation, upTo: 1)

        try await manager.reconfigureSession(
            conversationId: conversationId,
            config: spawnConfig(workingDirectory: "/tmp")
        )
        let maybeSecondSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let secondSubscription = try XCTUnwrap(maybeSecondSubscription)
        let secondEvent = try await nextEvent(from: secondSubscription.stream, description: "second AgentCLIKit launch event")

        XCTAssertEqual(firstEvent, .message(role: "assistant", content: "first", parentToolUseId: nil))
        XCTAssertEqual(secondEvent, .message(role: "assistant", content: "second", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitRespawnDoesNotReplayRetainedRuntimeEvents() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: ModelEchoingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-respawn-replay"

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: "/tmp", model: "first")
        )
        let maybeFirstSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let firstSubscription = try XCTUnwrap(maybeFirstSubscription)
        let firstEvent = try await nextEvent(from: firstSubscription.stream, description: "first AgentCLIKit respawn event")
        await manager.markPersisted(conversationId: conversationId, generation: firstSubscription.generation, upTo: 1)
        try await waitUntil("expected first AgentCLIKit runtime to exit") {
            !(await manager.isRunning(conversationId: conversationId))
        }

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: "/tmp", model: "second")
        )
        let maybeSecondSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let secondSubscription = try XCTUnwrap(maybeSecondSubscription)
        let secondEvent = try await nextEvent(from: secondSubscription.stream, description: "second AgentCLIKit respawn event")

        XCTAssertEqual(firstEvent, .message(role: "assistant", content: "first", parentToolUseId: nil))
        XCTAssertEqual(secondEvent, .message(role: "assistant", content: "second", parentToolUseId: nil))
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitMarkPersistedCompactsLocalReplayBuffer() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-mark-persisted-compaction"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }
        let maybeBufferGeneration = await manager.eventBuffers[conversationId]?.generation
        let bufferGeneration = try XCTUnwrap(maybeBufferGeneration)
        await manager.scheduleBufferCleanup(for: conversationId, generation: bufferGeneration, delay: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(50))
        let maybeSubscription = await awaitedSubscription(manager, conversationId: conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)

        for index in 1...5_301 {
            await manager.handleStreamEvent(
                .message(role: "assistant", content: "\(index)", parentToolUseId: nil),
                conversationId: conversationId,
                generation: subscription.generation,
                providerId: "claude"
            )
        }
        let retainedBeforeMark = await manager.retainedEventCount(conversationId: conversationId)
        XCTAssertGreaterThan(retainedBeforeMark, 5_200)

        await manager.markPersisted(conversationId: conversationId, generation: subscription.generation, upTo: 5_200)
        await manager.handleStreamEvent(
            .message(role: "assistant", content: "after", parentToolUseId: nil),
            conversationId: conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        let retainedAfterMark = await manager.retainedEventCount(conversationId: conversationId)
        XCTAssertLessThanOrEqual(retainedAfterMark, 5_000)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitIgnoresLiveHookRequestAfterConversationCloseStarts() async throws {
        let executable = try makeScript(named: "slow-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-closing-live-hook"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        await manager.kill(conversationId: conversationId)
        await manager.handleDeferredToolRequestFromHookServer(
            ClaudeDeferredToolRequest(
                conversationId: conversationId,
                launchToken: nil,
                request: ToolApprovalRequest(
                    sessionId: "session-1",
                    toolUseId: "tool-1",
                    toolName: "Bash",
                    toolInput: #"{"command":"pwd"}"#
                )
            )
        )

        XCTAssertNotEqual(manager.status(for: conversationId), .waitingForUser)
    }

    func makeAgentCLIKitFixture(
        adapter: any AgentCLIKit.AgentProviderAdapter,
        detectedPath: String,
        basePath: String, replayLimit: Int = 500
    ) -> AgentCLIKitManagerFixture {
        let sessionStore = AgentCLIKit.JSONFileAgentSessionStore(fileURL: temporaryFileURL("agentclikit-sessions.json"))
        let configStore = AgentCLIKit.ClaudeConfigStore(fileURL: temporaryFileURL("claude.json"))
        let approvalStore = AgentCLIKit.ClaudeApprovalPolicyStore()
        let liveHookDecisionProvider = AgentCLIKitLiveHookDecisionProvider()
        let runtime = AgentCLIKit.DefaultAgentRuntime(adapters: [adapter], sessionStore: sessionStore, replayLimit: replayLimit)
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
            liveHookDecisionProvider: liveHookDecisionProvider,
            contextWindowCache: AgentCLIKit.JSONAgentModelContextWindowCache(fileURL: temporaryFileURL("context.json")),
            hostAdapter: AgentCLIKitHostAdapter()
        )
        let manager = DefaultAgentsManager(
            agentCLIKitServices: services,
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(resolvedPath: detectedPath),
            environmentBuilder: FixedPathEnvironmentBuilder(path: basePath),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: makeSettings(),
            keepAwakeService: RecordingKeepAwakeService(),
            notificationManager: StubNotificationManager()
        )
        return AgentCLIKitManagerFixture(
            manager: manager,
            runtime: runtime,
            sessionStore: sessionStore,
            approvalStore: approvalStore,
            liveHookDecisionProvider: liveHookDecisionProvider
        )
    }

    func spawnConfig(providerId: String = "claude", workingDirectory: String, model: String? = nil) -> Alveary.AgentSpawnConfig {
        Alveary.AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: nil,
            model: model,
            effort: nil,
            initialPrompt: nil
        )
    }

    func awaitedSubscription(
        _ manager: DefaultAgentsManager,
        conversationId: String,
        afterIndex: Int
    ) async -> Alveary.AgentEventSubscription? {
        await manager.subscribe(conversationId: conversationId, afterIndex: afterIndex)
    }

    private func temporaryFileURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    func makeScript(named name: String, body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func nextEvent(
        from stream: AsyncStream<ConversationEvent>,
        description: String
    ) async throws -> ConversationEvent {
        try await withThrowingTaskGroup(of: ConversationEvent?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw WaitTimeoutError(description: description)
            }
            defer { group.cancelAll() }
            if let event = try await group.next() ?? nil {
                return event
            }
            throw WaitTimeoutError(description: description)
        }
    }
}

private struct FixedPathEnvironmentBuilder: AgentEnvironmentBuilder {
    let path: String

    func buildEnvironment(providerEnv: [String: String]?) -> [String: String] {
        var environment = [
            "HOME": NSHomeDirectory(),
            "PATH": path
        ]
        if let providerEnv {
            environment.merge(providerEnv) { _, new in new }
        }
        return environment
    }
}

struct PathResolvingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let executableName: String
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
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }
}

private struct ResolvingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
                "printf 'interaction:tool\\n'; read resolution; printf 'message:resolved:%s\\n' \"$resolution\""
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if line == "interaction:tool" {
            return [.interaction(AgentCLIKit.AgentInteractionEvent(
                id: "tool-1",
                kind: .approval,
                prompt: "Bash",
                metadata: [
                    "session_id": .string("session-1"),
                    "tool_name": .string("Bash"),
                    "tool_input": .object(["command": .string("pwd")])
                ]
            ))]
        }
        if let message = line.removingPrefix("message:") {
            return [.message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: message))]
        }
        return []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .userMessage, .interrupt:
            return Data()
        case .interactionResolution(let resolution):
            return Data("\(resolution.outcome.rawValue)\n".utf8)
        }
    }
}
