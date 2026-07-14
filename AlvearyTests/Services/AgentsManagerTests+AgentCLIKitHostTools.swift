import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentSpawnConfigWithoutHostToolsPreservesLaunchSettings() {
        let configured = hostToolTestConfig(
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )

        XCTAssertEqual(configured.withoutHostTools(), hostToolTestConfig())
    }

    func testAgentSpawnConfigWithoutHostToolsPreservesRootSnapshotsAfterSymlinkReplacement() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentSpawnConfigRootSnapshot-\(UUID().uuidString)", isDirectory: true)
        let grantedRootURL = baseURL.appendingPathComponent("granted-root", isDirectory: true)
        let replacementURL = baseURL.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: grantedRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let configured = hostToolTestConfig(
            additionalWorkspaceRoots: [grantedRootURL.path],
            allowedDirectories: [grantedRootURL.path],
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )
        let expectedAdditionalRoots = configured.additionalWorkspaceRoots
        let expectedAllowedDirectories = configured.allowedDirectories

        try FileManager.default.removeItem(at: grantedRootURL)
        try FileManager.default.createSymbolicLink(at: grantedRootURL, withDestinationURL: replacementURL)

        let fallback = configured.withoutHostTools()

        XCTAssertEqual(fallback.additionalWorkspaceRoots, expectedAdditionalRoots)
        XCTAssertEqual(fallback.allowedDirectories, expectedAllowedDirectories)
        XCTAssertNotEqual(fallback.additionalWorkspaceRoots, [CanonicalPath.normalize(grantedRootURL.path)])
    }

    func testHostToolFailureNoticeDisablesToolsForSession() async {
        let manager = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-host-tool-unavailable"

        await manager.markSchedulingHostToolsUnavailable(
            conversationId: conversationId,
            requiresRuntimeReplacement: true
        )

        let state = manager.conversationState(for: conversationId)
        XCTAssertTrue(state.schedulingHostToolsDisabled)
        XCTAssertTrue(state.requiresSchedulingHostToolReplacement)
        XCTAssertEqual(
            state.sessionContinuityNotice,
            "Natural-language scheduling is unavailable for this task. You can still manage schedules from Scheduled."
        )
    }

    func testHostToolFailureDiagnosticIgnoresReplacedSubscriptionAndOlderReplayGeneration() async throws {
        let fixture = await makeHostToolDiagnosticSubscriptionFixture()
        defer { fixture.finish() }
        let maybeSubscription = await fixture.manager.subscribe(conversationId: fixture.conversationId, afterIndex: 0)
        let subscription = try XCTUnwrap(maybeSubscription)

        fixture.oldContinuation.yield(hostToolUnavailableEnvelope(
            generation: 1,
            index: 1,
            conversationId: fixture.conversationId
        ))
        fixture.currentContinuation.yield(hostToolUnavailableEnvelope(
            generation: 1,
            index: 2,
            conversationId: fixture.conversationId
        ))
        fixture.currentContinuation.yield(messageEnvelope(
            generation: 2,
            index: 3,
            conversationId: fixture.conversationId,
            text: "current generation"
        ))

        let event = try await nextEvent(
            from: subscription.stream,
            description: "current event after stale host-tool diagnostics"
        )
        XCTAssertEqual(event, .message(role: "assistant", content: "current generation", parentToolUseId: nil))
        XCTAssertFalse(fixture.manager.conversationState(for: fixture.conversationId).schedulingHostToolsDisabled)

        fixture.currentContinuation.yield(hostToolUnavailableEnvelope(
            generation: 2,
            index: 4,
            conversationId: fixture.conversationId
        ))
        try await waitUntil("expected current host-tool diagnostic to disable scheduling tools") {
            fixture.manager.conversationState(for: fixture.conversationId).schedulingHostToolsDisabled
        }
    }

    func testFallbackDecisionAcceptsExplicitCodexThreadHostToolPolicyFailures() {
        let config = hostToolTestConfig(
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )
        let failures = [
            SchedulingHostToolLaunchFailure.codexThreadJSONRPC(
                method: "thread/start",
                message: "Unknown configuration key mcp_servers"
            ),
            .codexThreadJSONRPC(
                method: "thread/start",
                message: "Unknown server alveary_host"
            ),
            .codexThreadJSONRPC(
                method: "thread/resume",
                message: "Invalid value for enabled_tools"
            ),
            .codexThreadJSONRPC(
                method: "thread/fork",
                message: "Unsupported field approval_mode"
            )
        ]

        for failure in failures {
            XCTAssertEqual(
                SchedulingHostToolFallbackClassifier.decision(for: failure, config: config),
                .retryWithoutHostTools
            )
        }
    }

    func testFallbackDecisionRejectsUnrelatedCodexAndProviderFailures() {
        let codexConfig = hostToolTestConfig(
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )
        let unrelatedFailures = [
            SchedulingHostToolLaunchFailure.codexThreadJSONRPC(
                method: "turn/start",
                message: "Invalid value for mcp_servers.alveary_host"
            ),
            .codexThreadJSONRPC(
                method: "thread/start",
                message: "Model is unavailable"
            ),
            .codexThreadJSONRPC(
                method: "thread/start",
                message: "MCP server initialization failed"
            ),
            .unrelated
        ]

        for failure in unrelatedFailures {
            XCTAssertEqual(
                SchedulingHostToolFallbackClassifier.decision(for: failure, config: codexConfig),
                .propagate
            )
        }

        let claudeConfig = hostToolTestConfig(
            providerId: "claude",
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )
        XCTAssertEqual(
            SchedulingHostToolFallbackClassifier.decision(
                for: .codexThreadJSONRPC(method: "thread/start", message: "Invalid enabled_tools"),
                config: claudeConfig
            ),
            .propagate
        )
    }

    func testFallbackDecisionRequiresConfiguredToolsAndRetainsNativeFallback() {
        XCTAssertEqual(
            SchedulingHostToolFallbackClassifier.decision(
                for: .codexThreadJSONRPC(method: "thread/start", message: "Invalid mcp_servers"),
                config: hostToolTestConfig()
            ),
            .propagate
        )
        XCTAssertEqual(
            SchedulingHostToolFallbackClassifier.decision(
                for: .hostToolsUnavailable,
                config: hostToolTestConfig(hostTools: [hostToolTestDefinition])
            ),
            .retryWithoutHostTools
        )
    }

    private func hostToolTestConfig(
        providerId: String = "codex",
        additionalWorkspaceRoots: [String] = ["/tmp/grant"],
        allowedDirectories: [String] = ["/tmp/allowed"],
        hostToolServer: AgentHostToolServerMetadata = AgentHostToolServerMetadata(),
        hostTools: [AgentHostToolDefinition] = []
    ) -> Alveary.AgentSpawnConfig {
        Alveary.AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: "/tmp/project",
            permissionMode: "on-request",
            planModeEnabled: true,
            model: "gpt-5",
            effort: "high",
            reasoningSummaryMode: .detailed,
            speedMode: .fast,
            sessionFork: AgentSessionForkRequest(
                sourceSessionId: "source-session",
                sourceWorkingDirectory: "/tmp/source",
                mode: .worktree
            ),
            initialPrompt: "Continue",
            initialPromptMetadata: ["source": .string("test")],
            additionalWorkspaceRoots: additionalWorkspaceRoots,
            allowedDirectories: allowedDirectories,
            hostToolServer: hostToolServer,
            hostTools: hostTools,
            initialGoal: "Finish the task",
            isAutomatedScheduledTurn: true
        )
    }

    private func makeHostToolDiagnosticSubscriptionFixture() async -> HostToolDiagnosticSubscriptionFixture {
        let manager = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/usr/bin/agent",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-stale-host-tool-diagnostic"
        let config = hostToolTestConfig(
            hostToolServer: AgentHostToolServerMetadata(name: "alveary_host"),
            hostTools: [hostToolTestDefinition]
        )
        let oldEvents = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        let currentEvents = AsyncStream<AgentCLIKit.AgentEventEnvelope>.makeStream()
        await manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: config,
            subscription: AgentCLIKit.AgentEventSubscription(generation: 1, events: oldEvents.stream)
        )
        await manager.installAgentCLIKitSubscriptionBuffer(
            conversationId: conversationId,
            config: config,
            subscription: AgentCLIKit.AgentEventSubscription(generation: 2, events: currentEvents.stream)
        )
        return HostToolDiagnosticSubscriptionFixture(
            manager: manager,
            conversationId: conversationId,
            oldContinuation: oldEvents.continuation,
            currentContinuation: currentEvents.continuation
        )
    }
}

private struct HostToolDiagnosticSubscriptionFixture {
    let manager: DefaultAgentsManager
    let conversationId: String
    let oldContinuation: AsyncStream<AgentCLIKit.AgentEventEnvelope>.Continuation
    let currentContinuation: AsyncStream<AgentCLIKit.AgentEventEnvelope>.Continuation

    func finish() {
        oldContinuation.finish()
        currentContinuation.finish()
    }
}

private func hostToolUnavailableEnvelope(
    generation: Int,
    index: Int,
    conversationId: String
) -> AgentCLIKit.AgentEventEnvelope {
    AgentCLIKit.AgentEventEnvelope(
        generation: generation,
        index: index,
        providerId: .claude,
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        providerSessionId: nil,
        source: .runtime,
        event: .diagnostic(AgentCLIKit.AgentDiagnosticEvent(
            code: .hostToolServerUnavailable,
            severity: .error,
            message: "Host tool listener stopped unexpectedly."
        )),
        createdAt: Date(timeIntervalSince1970: Double(index))
    )
}

private func messageEnvelope(
    generation: Int,
    index: Int,
    conversationId: String,
    text: String
) -> AgentCLIKit.AgentEventEnvelope {
    AgentCLIKit.AgentEventEnvelope(
        generation: generation,
        index: index,
        providerId: .claude,
        conversationId: AgentCLIKit.AgentConversationID(rawValue: conversationId),
        providerSessionId: nil,
        source: .runtime,
        event: .message(AgentCLIKit.AgentMessageEvent(role: .assistant, text: text)),
        createdAt: Date(timeIntervalSince1970: Double(index))
    )
}

private let hostToolTestDefinition = AgentHostToolDefinition(
    name: "list_scheduled_tasks",
    description: "Lists scheduled tasks.",
    inputSchema: .object(["type": .string("object")])
)
