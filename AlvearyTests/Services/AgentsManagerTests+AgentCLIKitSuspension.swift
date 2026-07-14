import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testAgentCLIKitSuspendIdleRuntimePreservesResumableState() async throws {
        let executable = try makeScript(named: "suspend-idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let launchRecorder = PathResolvingLaunchRecorder()
        let fixture = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(
                executableName: executable.lastPathComponent,
                launchRecorder: launchRecorder
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        )
        let context = try await seedSuspensionState(fixture, executable: executable)

        try await fixture.manager.spawn(
            id: context.conversationId,
            config: spawnConfig(workingDirectory: context.workingDirectory.path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            fixture.manager.status(for: context.conversationId) == .idle
        }
        await fixture.manager.suspendRuntime(conversationId: context.conversationId)
        await fixture.manager.suspendRuntime(conversationId: context.conversationId)

        try await assertSuspensionPreservedState(context, fixture: fixture)

        try await fixture.manager.spawn(
            id: context.conversationId,
            config: spawnConfig(workingDirectory: context.workingDirectory.path)
        )
        try await waitUntil("expected suspended AgentCLIKit runtime to resume") {
            await fixture.manager.isRunning(conversationId: context.conversationId)
        }
        let recordedLaunches = await launchRecorder.values()
        let resumedLaunch = try XCTUnwrap(recordedLaunches.last)
        XCTAssertEqual(resumedLaunch.resumedProviderSessionID, "provider-session")
        XCTAssertFalse(resumedLaunch.forksSession)
        await fixture.manager.kill(conversationId: context.conversationId)
    }

    func testAgentCLIKitSuspendDoesNotStopActiveTurn() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-suspend-active-runtime"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        )
        try await manager.sendMessage("start", conversationId: conversationId)
        try await waitUntil("expected AgentCLIKit runtime to report an active turn") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.isTurnActive == true
        }
        await manager.suspendRuntime(conversationId: conversationId)

        let isRunning = await manager.isRunning(conversationId: conversationId)
        let remainsActive = await fixture.runtime.status(conversationId: runtimeConversationId)?.isTurnActive
        XCTAssertTrue(isRunning)
        XCTAssertEqual(remainsActive, true)
        try await manager.sendMessage("finish", conversationId: conversationId)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitSuspendCanRetryAfterTerminalEventLeadsRuntimeStatus() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-suspend-terminal-status-lag"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        )
        try await manager.sendMessage("start", conversationId: conversationId)
        try await waitUntil("expected AgentCLIKit runtime to report an active turn") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.isTurnActive == true
        }
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)
        await manager.handleStreamEvent(
            suspensionLagTerminalEvent(),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude",
            runtimeEventIndex: Int.max
        )
        XCTAssertEqual(manager.status(for: conversationId), .idle)

        await manager.suspendRuntime(conversationId: conversationId)

        let hasTrackedLaggingProcess = await manager.hasTrackedProcess(conversationId: conversationId)
        let laggingRuntimeIsSuspended = await manager.isRuntimeSuspended(conversationId: conversationId)
        let laggingTurnIsActive = await fixture.runtime.status(conversationId: runtimeConversationId)?.isTurnActive
        XCTAssertTrue(hasTrackedLaggingProcess)
        XCTAssertFalse(laggingRuntimeIsSuspended)
        XCTAssertEqual(
            laggingTurnIsActive,
            true
        )

        try await manager.sendMessage("finish", conversationId: conversationId)
        try await waitUntil("expected raw AgentCLIKit status to catch up with the terminal event") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.isTurnActive == false
        }
        await manager.suspendRuntime(conversationId: conversationId)

        let hasTrackedSuspendedProcess = await manager.hasTrackedProcess(conversationId: conversationId)
        let runtimeIsSuspended = await manager.isRuntimeSuspended(conversationId: conversationId)
        XCTAssertFalse(hasTrackedSuspendedProcess)
        XCTAssertTrue(runtimeIsSuspended)
    }

    func testAgentCLIKitSuspendDoesNotStopRuntimeWaitingForUser() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: WaitingStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-suspend-waiting-runtime"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        )
        try await waitUntil("expected AgentCLIKit runtime to wait for a prompt response") {
            await fixture.runtime.status(conversationId: runtimeConversationId)?.waitingState == .prompt
        }
        await manager.suspendRuntime(conversationId: conversationId)

        let isRunning = await manager.isRunning(conversationId: conversationId)
        let waitingState = await fixture.runtime.status(conversationId: runtimeConversationId)?.waitingState
        XCTAssertTrue(isRunning)
        XCTAssertEqual(waitingState, .prompt)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitOutboundReadinessWaitsForInFlightSuspension() async throws {
        let executable = try makeScript(named: "suspend-readiness-race-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let terminationGate = SuspensionAsyncGate()
        let fixture = makeBlockingSuspensionFixture(
            adapter: BlockingSuspensionAgentCLIKitAdapter(
                executableName: executable.lastPathComponent,
                terminationGate: terminationGate
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            approvalStore: BlockingSuspensionApprovalStore(removalGate: SuspensionAsyncGate())
        )
        let conversationId = "agentclikit-suspend-readiness-race"
        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            fixture.manager.status(for: conversationId) == .idle
        }

        let suspension = Task {
            await fixture.manager.suspendRuntime(conversationId: conversationId)
        }
        try await waitForSuspensionGate(terminationGate, description: "expected suspension teardown to block")

        let readiness = try await startPendingOutboundReadiness(
            manager: fixture.manager,
            conversationId: conversationId
        )

        await terminationGate.open()
        let result = await readiness.task.value
        await suspension.value
        XCTAssertEqual(result, .respawnRequired)
    }

    func testAgentCLIKitOutboundReadinessBlocksWhenCancelledDuringSuspension() async throws {
        let executable = try makeScript(named: "suspend-readiness-cancel-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let terminationGate = SuspensionAsyncGate()
        let fixture = makeBlockingSuspensionFixture(
            adapter: BlockingSuspensionAgentCLIKitAdapter(
                executableName: executable.lastPathComponent,
                terminationGate: terminationGate
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            approvalStore: BlockingSuspensionApprovalStore(removalGate: SuspensionAsyncGate())
        )
        let conversationId = "agentclikit-suspend-readiness-cancel"
        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            fixture.manager.status(for: conversationId) == .idle
        }

        let suspension = Task {
            await fixture.manager.suspendRuntime(conversationId: conversationId)
        }
        try await waitForSuspensionGate(terminationGate, description: "expected suspension teardown to block")
        let readiness = try await startPendingOutboundReadiness(
            manager: fixture.manager,
            conversationId: conversationId
        )

        readiness.task.cancel()
        try await waitUntil("expected cancellation to finish readiness before suspension timeout") {
            readiness.result.withLock { $0 } != nil
        }
        let cancelledReadiness = await readiness.task.value
        XCTAssertEqual(
            cancelledReadiness,
            .blocked(reason: "Outbound request was cancelled")
        )

        await terminationGate.open()
        await suspension.value
    }

    func testAgentCLIKitOutboundReadinessBlocksWhenConversationClosesDuringSuspension() async throws {
        let executable = try makeScript(named: "suspend-readiness-close-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let terminationGate = SuspensionAsyncGate()
        let fixture = makeBlockingSuspensionFixture(
            adapter: BlockingSuspensionAgentCLIKitAdapter(
                executableName: executable.lastPathComponent,
                terminationGate: terminationGate
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            approvalStore: BlockingSuspensionApprovalStore(removalGate: SuspensionAsyncGate())
        )
        let conversationId = "agentclikit-suspend-readiness-close"
        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            fixture.manager.status(for: conversationId) == .idle
        }

        let suspension = Task {
            await fixture.manager.suspendRuntime(conversationId: conversationId)
        }
        try await waitForSuspensionGate(terminationGate, description: "expected suspension teardown to block")
        let readiness = try await startPendingOutboundReadiness(
            manager: fixture.manager,
            conversationId: conversationId
        )

        await fixture.manager.kill(conversationId: conversationId)
        try await waitUntil("expected closing state to finish readiness before suspension timeout") {
            readiness.result.withLock { $0 } != nil
        }
        let closingReadiness = await readiness.task.value
        XCTAssertEqual(
            closingReadiness,
            .blocked(reason: "Conversation is closing")
        )

        await terminationGate.open()
        await suspension.value
        try await fixture.manager.destroyRuntime(conversationId: conversationId)
    }

    func testAgentCLIKitDestructiveTeardownWaitsForInFlightSuspension() async throws {
        let executable = try makeScript(named: "suspend-delete-race-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let terminationGate = SuspensionAsyncGate()
        let approvalRemovalGate = SuspensionAsyncGate()
        let approvalStore = BlockingSuspensionApprovalStore(removalGate: approvalRemovalGate)
        let fixture = makeBlockingSuspensionFixture(
            adapter: BlockingSuspensionAgentCLIKitAdapter(
                executableName: executable.lastPathComponent,
                terminationGate: terminationGate
            ),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin",
            approvalStore: approvalStore
        )
        let conversationId = "agentclikit-suspend-delete-race"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        try await seedBlockingSuspensionSession(
            fixture: fixture,
            runtimeConversationId: runtimeConversationId,
            workingDirectory: executable.deletingLastPathComponent()
        )
        try await fixture.manager.spawn(
            id: conversationId,
            config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path)
        )
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            fixture.manager.status(for: conversationId) == .idle
        }

        let suspension = Task {
            await fixture.manager.suspendRuntime(conversationId: conversationId)
        }
        try await waitForSuspensionGate(terminationGate, description: "expected non-destructive suspension teardown to block")
        await fixture.manager.kill(conversationId: conversationId)
        let destructiveTeardown = Task {
            try await fixture.manager.destroyRuntime(conversationId: conversationId)
        }

        await terminationGate.open()
        try await waitForSuspensionGate(approvalRemovalGate, description: "expected destructive approval cleanup to block")

        await assertSuspensionTeardownTombstonesArePreserved(
            manager: fixture.manager,
            conversationId: conversationId
        )

        await approvalRemovalGate.open()
        try await destructiveTeardown.value
        await suspension.value

        let providerSession = try await fixture.sessionStore.record(
            conversationId: runtimeConversationId,
            providerId: .claude
        )
        XCTAssertNil(providerSession)
    }

    private func seedSuspensionState(
        _ fixture: AgentCLIKitManagerFixture,
        executable: URL
    ) async throws -> SuspensionTestContext {
        let conversationId = "agentclikit-suspend-idle-runtime"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        let workingDirectory = executable.deletingLastPathComponent()
        let originalState = fixture.manager.conversationState(for: conversationId)
        originalState.inputDraft = "Retain me"
        _ = await fixture.sessionManager.createEntry(
            conversationId: conversationId,
            cwd: workingDirectory.path,
            providerId: "claude"
        )
        let alvearySessionId = await fixture.sessionManager.sessionId(for: conversationId)
        let approvalRequest = makeSuspensionApprovalRequest(conversationId: runtimeConversationId)
        let approvalGrant = try XCTUnwrap(approvalRequest.sessionApprovalGrant(for: .exact))
        try await fixture.sessionStore.save(AgentCLIKit.AgentSessionRecord(
            conversationId: runtimeConversationId,
            providerId: .claude,
            providerSessionId: "provider-session",
            workingDirectory: workingDirectory,
            generation: 1
        ))
        _ = await fixture.approvalStore.recordSessionApproval(approvalGrant)
        return SuspensionTestContext(
            conversationId: conversationId,
            runtimeConversationId: runtimeConversationId,
            workingDirectory: workingDirectory,
            originalState: originalState,
            alvearySessionId: alvearySessionId,
            approvalRequest: approvalRequest
        )
    }

    private func assertSuspensionPreservedState(
        _ context: SuspensionTestContext,
        fixture: AgentCLIKitManagerFixture
    ) async throws {
        let isRunning = await fixture.manager.isRunning(conversationId: context.conversationId)
        let readiness = await fixture.manager.outboundReadiness(conversationId: context.conversationId)
        let hasAlvearySession = await fixture.sessionManager.hasSession(for: context.conversationId)
        let alvearySessionId = await fixture.sessionManager.sessionId(for: context.conversationId)
        let providerSession = try await fixture.sessionStore.record(
            conversationId: context.runtimeConversationId,
            providerId: .claude
        )
        let allowsApproval = await fixture.approvalStore.allowsSessionApproval(context.approvalRequest)

        XCTAssertFalse(isRunning)
        XCTAssertEqual(readiness, .respawnRequired)
        XCTAssertIdentical(fixture.manager.conversationState(for: context.conversationId), context.originalState)
        XCTAssertEqual(context.originalState.inputDraft, "Retain me")
        XCTAssertTrue(hasAlvearySession)
        XCTAssertEqual(alvearySessionId, context.alvearySessionId)
        XCTAssertNotNil(providerSession)
        XCTAssertTrue(allowsApproval)
    }

    private func startPendingOutboundReadiness(
        manager: DefaultAgentsManager,
        conversationId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (
        task: Task<AgentOutboundReadiness, Never>,
        result: LockedState<AgentOutboundReadiness?>
    ) {
        let readinessStarted = LockedState(false)
        let readinessResult = LockedState<AgentOutboundReadiness?>(nil)
        let readiness = Task {
            readinessStarted.withLock { $0 = true }
            let result = await manager.outboundReadiness(conversationId: conversationId)
            readinessResult.withLock { $0 = result }
            return result
        }
        try await waitUntil("expected outbound readiness check to start") {
            readinessStarted.withLock { $0 }
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(readinessResult.withLock { $0 }, file: file, line: line)
        return (readiness, readinessResult)
    }
}

private func suspensionLagTerminalEvent() -> ConversationEvent {
    .tokens(
        input: 1,
        output: 1,
        cacheRead: 0,
        isError: false,
        stopReason: "end_turn",
        durationMs: 1,
        costUsd: 0,
        permissionDenials: [],
        isTerminal: true
    )
}

private struct SuspensionTestContext {
    let conversationId: String
    let runtimeConversationId: AgentCLIKit.AgentConversationID
    let workingDirectory: URL
    let originalState: ConversationState
    let alvearySessionId: String
    let approvalRequest: AgentCLIKit.AgentSessionApprovalRequest
}

private struct WaitingStatusAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
            arguments: ["-c", "printf 'interaction:prompt\\n'; read resolution; sleep 1"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        guard line == "interaction:prompt" else {
            return []
        }
        return [.interaction(AgentCLIKit.AgentInteractionEvent(
            id: "prompt-1",
            kind: .prompt,
            prompt: "Pick one"
        ))]
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        switch input {
        case .interactionResolution(let resolution):
            return Data("\(resolution.outcome.rawValue)\n".utf8)
        case .userMessage, .interrupt:
            return Data()
        }
    }
}

private func makeSuspensionApprovalRequest(
    conversationId: AgentCLIKit.AgentConversationID
) -> AgentCLIKit.AgentSessionApprovalRequest {
    AgentCLIKit.AgentSessionApprovalRequest(
        providerId: .claude,
        conversationId: conversationId,
        sessionId: "provider-session",
        toolName: "Read",
        toolInput: .object(["file_path": .string("/tmp/file.txt")])
    )
}
