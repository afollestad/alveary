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

        try await waitUntil("expected live tool approval to show waiting status") {
            fixture.manager.status(for: fixture.conversationId) == .waitingForUser
        }

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

    func testToolApprovalWaitingKeepsRuntimeAwakeUntilApprovalFailureClearsIt() async throws {
        let fixture = try makeStatusFixture(conversationId: "conversation-approval-waiting-keep-awake")
        defer { fixture.cleanup() }

        let subscription = try await fixture.start()
        let approval = bashApprovalRequest(command: "date")
        await fixture.manager.handleStreamEvent(
            .toolApprovalRequested(approval),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        try await waitUntil("expected pending approval to keep Mac awake") {
            fixture.manager.status(for: fixture.conversationId) == .waitingForUser &&
                fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        await fixture.manager.handleStreamEvent(
            .toolApprovalFailed(ToolApprovalFailure(
                sessionId: approval.sessionId,
                toolUseId: approval.toolUseId,
                toolName: approval.toolName,
                message: "Hook failed"
            )),
            conversationId: fixture.conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )

        try await waitUntil("expected approval failure to return to busy status") {
            fixture.manager.status(for: fixture.conversationId) == .busy
        }
    }

    func testBusyAndWaitingStatusesKeepAwakeActiveUntilRuntimeClears() async throws {
        let fixture = try makeStatusFixture(conversationId: "conversation-keep-awake-status")
        defer { fixture.cleanup() }

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        try await waitUntil("expected busy runtime to keep Mac awake") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.waitingForUser, for: fixture.conversationId)
        try await waitUntil("expected waiting runtime to keep Mac awake") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.idle, for: fixture.conversationId)
        try await waitUntil("expected idle runtime to clear keep-awake activity") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        try await waitUntil("expected busy runtime to keep Mac awake again") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.error, for: fixture.conversationId)
        try await waitUntil("expected error runtime to clear keep-awake activity") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        try await waitUntil("expected busy runtime to keep Mac awake before stopped status") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.stopped, for: fixture.conversationId)
        try await waitUntil("expected stopped runtime to clear keep-awake activity") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        try await waitUntil("expected busy runtime to keep Mac awake before neutral status") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.neutral, for: fixture.conversationId)
        try await waitUntil("expected neutral runtime to clear keep-awake activity") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        try await waitUntil("expected busy runtime to keep Mac awake before clearStatus") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.clearStatus(for: fixture.conversationId)
        try await waitUntil("expected clearStatus to keep runtime activity clear") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }
    }

    func testRuntimeKeepAwakeStaysActiveForBackgroundConversation() async throws {
        let fixture = try makeStatusFixture(conversationId: "conversation-keep-awake-status")
        defer { fixture.cleanup() }
        let backgroundConversationId = "conversation-keep-awake-background-status"

        fixture.manager.updateStatus(.busy, for: fixture.conversationId)
        fixture.manager.updateStatus(.busy, for: backgroundConversationId)
        try await waitUntil("expected busy runtimes to keep Mac awake") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.updateStatus(.idle, for: fixture.conversationId)
        try await waitUntil("expected second busy runtime to keep Mac awake") {
            fixture.keepAwakeService.isActive(.runtimeActivity)
        }

        fixture.manager.clearStatus(for: backgroundConversationId)
        try await waitUntil("expected final cleared runtime to release keep-awake activity") {
            !fixture.keepAwakeService.isActive(.runtimeActivity)
        }
    }
}

@MainActor
private struct AgentsManagerStatusFixture {
    let executable: TempExecutable
    let manager: DefaultAgentsManager
    let keepAwakeService: RecordingKeepAwakeService
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
        let keepAwakeService = RecordingKeepAwakeService()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            keepAwakeService: keepAwakeService,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        return AgentsManagerStatusFixture(
            executable: executable,
            manager: manager,
            keepAwakeService: keepAwakeService,
            conversationId: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        )
    }
}
