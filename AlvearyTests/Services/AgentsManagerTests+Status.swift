import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testPermissionDenialTokenDoesNotLeaveRuntimeInErrorStatus() async throws {
        let fixture = try makeStatusFixture(conversationId: "conversation-permission-denial-status")
        defer { fixture.cleanup() }

        let subscription = try await fixture.start()
        await fixture.manager.handleStreamEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "permission denied",
                durationMs: 5,
                costUsd: 0,
                permissionDenials: [PermissionDenialSummary(toolName: "Bash", toolUseId: "tool-1")]
            ),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        XCTAssertEqual(fixture.manager.status(for: fixture.conversationId), .idle)
    }

    func testErrorTokenWithoutPermissionDenialsLeavesRuntimeInErrorStatus() async throws {
        let fixture = try makeStatusFixture(conversationId: "conversation-real-error-status")
        defer { fixture.cleanup() }

        let subscription = try await fixture.start()
        await fixture.manager.handleStreamEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "Agent process crashed unexpectedly",
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            ),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        XCTAssertEqual(fixture.manager.status(for: fixture.conversationId), .error)
    }

    func testLiveToolApprovalSetsStatusBusyAndCompletionClearsIt() async throws {
        let fixture = try makeApprovalFixture(
            conversationId: "conversation-hook-live-approval-status",
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        defer { fixture.cleanup() }

        try await fixture.start(description: "expected initial launch before live approval")
        guard let subscription = await fixture.manager.subscribe(conversationId: fixture.conversationId, afterIndex: 0) else {
            return XCTFail("Expected live event subscription")
        }

        let approval = bashApprovalRequest(command: "date")
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(
                conversationId: fixture.conversationId,
                launchToken: "approval-token",
                request: approval
            )
        )

        _ = try await fixture.manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: fixture.conversationId,
                approval: approval,
                resolution: ClaudeToolApprovalResolution(decision: .allow),
                additionalApprovals: [],
                sessionApproval: nil,
                config: fixture.config
            )
        )

        XCTAssertEqual(fixture.manager.status(for: fixture.conversationId), .busy)

        await fixture.manager.handleStreamEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            ),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        XCTAssertEqual(fixture.manager.status(for: fixture.conversationId), .idle)
    }
}

@MainActor
private struct AgentsManagerStatusFixture {
    let executable: TempExecutable
    let manager: DefaultAgentsManager
    let conversationId: String
    let config: AgentSpawnConfig

    func start() async throws -> AgentEventSubscription {
        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        guard let subscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            throw WaitTimeoutError(description: "Expected live event subscription")
        }
        return subscription
    }

    func cleanup() {
        executable.cleanup()
        Task { await manager.kill(conversationId: conversationId) }
    }
}

@MainActor
private extension AgentsManagerTests {
    func makeStatusFixture(conversationId: String) throws -> AgentsManagerStatusFixture {
        let executable = try TempExecutable()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        return AgentsManagerStatusFixture(
            executable: executable,
            manager: manager,
            conversationId: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        )
    }
}
