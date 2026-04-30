import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testInterimUsageTokensDoNotNotify() async throws {
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: "/bin/echo"),
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let event = ConversationEvent.tokens(
            input: 1,
            output: 2,
            cacheRead: 0,
            isError: false,
            stopReason: ConversationEvent.interimUsageStopReason,
            durationMs: 0,
            costUsd: 0,
            permissionDenials: []
        )

        let shouldNotify = await manager.shouldNotify(
            for: event,
            notificationEvent: event,
            conversationId: "conversation-interim-usage-notification"
        )

        XCTAssertFalse(shouldNotify)
    }

    func testQueuedCompletionTokenStillWaitsForQueueDrain() async throws {
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: "/bin/echo"),
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-queued-completion-notification"
        let state = manager.conversationState(for: conversationId)
        state.messageQueue.enqueue("Queued follow-up", stagedContext: nil)
        let event = ConversationEvent.tokens(
            input: 1,
            output: 2,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 5,
            costUsd: 0,
            permissionDenials: []
        )

        let shouldNotify = await manager.shouldNotify(
            for: event,
            notificationEvent: event,
            conversationId: conversationId
        )

        XCTAssertFalse(shouldNotify)
    }

    func testDeferredToolStopNotifiesAskUserQuestionInsteadOfCompletion() async throws {
        let executable = try TempDeferredToolExecutable()
        defer { executable.cleanup() }

        let notificationManager = RecordingNotificationManager()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            notificationManager: notificationManager,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-deferred-question-notification"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        try await waitUntil("expected deferred prompt runtime to stop after notification") {
            let isRunning = await manager.isRunning(conversationId: conversationId)
            return !isRunning && notificationManager.handleEventCalls.count == 1
        }

        let recordedEvent = try XCTUnwrap(notificationManager.handleEventCalls.first)
        XCTAssertEqual(recordedEvent.conversationId, conversationId)
        guard case .toolApprovalRequested(let request) = recordedEvent.event else {
            return XCTFail("Expected AskUserQuestion notification event")
        }
        XCTAssertEqual(request.toolName, "AskUserQuestion")
    }

    func testLiveHookApprovalNotifiesOnceWithApprovalRequest() async throws {
        let executable = try TempHookServerDeferredToolExecutable()
        defer { executable.cleanup() }
        let notificationManager = RecordingNotificationManager()
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            notificationManager: notificationManager,
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-live-approval-notification"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before live approval notification") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        await hookServer.emitDeferredToolRequest(
            liveBashApprovalRequest(conversationId: conversationId, toolUseId: "toolu_first", command: "date +%s")
        )

        try await waitUntil("expected live approval notification") {
            notificationManager.handleEventCalls.count == 1
        }

        let recordedEvent = try XCTUnwrap(notificationManager.handleEventCalls.first)
        guard case .toolApprovalRequested(let request) = recordedEvent.event else {
            return XCTFail("Expected tool approval notification event")
        }
        XCTAssertEqual(request.toolName, "Bash")
        XCTAssertEqual(request.conciseSummary, "date +%s")
    }

    func testParallelLiveHookApprovalsCoalesceToOneNotification() async throws {
        let executable = try TempHookServerDeferredToolExecutable()
        defer { executable.cleanup() }
        let notificationManager = RecordingNotificationManager()
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            notificationManager: notificationManager,
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-parallel-approval-notification"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before parallel approval notification") {
            await manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        await hookServer.emitDeferredToolRequest(
            liveBashApprovalRequest(conversationId: conversationId, toolUseId: "toolu_first", command: "date +%s")
        )
        await hookServer.emitDeferredToolRequest(
            liveBashApprovalRequest(conversationId: conversationId, toolUseId: "toolu_second", command: "pwd")
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(notificationManager.handleEventCalls.count, 1)
    }

    func testLiveApprovalResolutionAllowsLaterApprovalNotification() async throws {
        let fixture = try liveApprovalNotificationFixture()
        defer { fixture.executable.cleanup() }
        let conversationId = "conversation-later-approval-notification"
        defer {
            Task { await fixture.manager.kill(conversationId: conversationId) }
        }

        try await fixture.manager.spawn(id: conversationId, config: fixture.config, forkSession: false)
        try await waitUntil("expected first tool call before first approval notification") {
            await fixture.manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        let firstApproval = liveBashApprovalRequest(
            conversationId: conversationId,
            toolUseId: "toolu_first",
            command: "date +%s"
        ).request
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(conversationId: conversationId, launchToken: "token", request: firstApproval)
        )
        try await waitUntil("expected first approval notification") {
            fixture.notificationManager.handleEventCalls.count == 1
        }

        _ = try await fixture.manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversationId,
                approval: firstApproval,
                resolution: ClaudeToolApprovalResolution(decision: .allow),
                additionalApprovals: [],
                sessionApproval: nil,
                config: fixture.config
            )
        )

        await fixture.hookServer.emitDeferredToolRequest(
            liveBashApprovalRequest(conversationId: conversationId, toolUseId: "toolu_second", command: "pwd")
        )

        try await waitUntil("expected later approval notification") {
            fixture.notificationManager.handleEventCalls.count == 2
        }
    }

    func testLiveApprovalFailureAllowsLaterApprovalNotification() async throws {
        let fixture = try liveApprovalNotificationFixture()
        defer { fixture.executable.cleanup() }
        let conversationId = "conversation-failed-approval-later-notification"
        defer {
            Task { await fixture.manager.kill(conversationId: conversationId) }
        }

        try await fixture.manager.spawn(id: conversationId, config: fixture.config, forkSession: false)
        try await waitUntil("expected first tool call before failed approval notification") {
            await fixture.manager.retainedEventCount(conversationId: conversationId) >= 1
        }

        guard let subscription = await fixture.manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            return XCTFail("Expected live approval subscription")
        }
        let firstApproval = liveBashApprovalRequest(
            conversationId: conversationId,
            toolUseId: "toolu_first",
            command: "date +%s"
        ).request
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(conversationId: conversationId, launchToken: "token", request: firstApproval)
        )
        try await waitUntil("expected first failed-approval notification") {
            fixture.notificationManager.handleEventCalls.count == 1
        }

        await fixture.manager.handleStreamEvent(
            .toolApprovalFailed(ToolApprovalFailure(
                sessionId: firstApproval.sessionId,
                toolUseId: firstApproval.toolUseId,
                toolName: firstApproval.toolName,
                message: "Claude hook failed (PreToolUse:Bash): socket closed"
            )),
            conversationId: conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )
        await fixture.hookServer.emitDeferredToolRequest(
            liveBashApprovalRequest(conversationId: conversationId, toolUseId: "toolu_second", command: "pwd")
        )

        try await waitUntil("expected later notification after approval failure") {
            fixture.notificationManager.handleEventCalls.count == 2
        }
    }

    func testDeniedExitPlanModePermissionDenialDoesNotNotifyAgain() async throws {
        let fixture = try liveApprovalNotificationFixture()
        defer { fixture.executable.cleanup() }
        let conversationId = "conversation-denied-exit-plan-notification"
        let approval = ToolApprovalRequest(
            sessionId: "session-deferred",
            toolUseId: "toolu_exit_plan",
            toolName: "ExitPlanMode",
            toolInput: ##"{"plan":"# Plan"}"##
        )
        defer {
            Task { await fixture.manager.kill(conversationId: conversationId) }
        }

        try await fixture.manager.spawn(id: conversationId, config: fixture.config, forkSession: false)
        guard let subscription = await fixture.manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            return XCTFail("Expected live approval subscription")
        }
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(conversationId: conversationId, launchToken: "token", request: approval)
        )
        try await waitUntil("expected exit-plan approval notification") {
            fixture.notificationManager.handleEventCalls.count == 1
        }

        _ = try await fixture.manager.resolveToolApproval(
            AgentToolApprovalResolutionRequest(
                conversationId: conversationId,
                approval: approval,
                resolution: ClaudeToolApprovalResolution(decision: .deny),
                additionalApprovals: [],
                sessionApproval: nil,
                config: fixture.config
            )
        )
        await fixture.manager.handleStreamEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: true,
                stopReason: "permission denied",
                durationMs: 5,
                costUsd: 0,
                permissionDenials: [PermissionDenialSummary(toolName: "ExitPlanMode", toolUseId: approval.toolUseId)]
            ),
            conversationId: conversationId,
            generation: subscription.generation,
            providerId: "claude"
        )
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(fixture.notificationManager.handleEventCalls.count, 1)
    }

    func testInterruptedTrailingErrorTokensDoNotNotify() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let notificationManager = RecordingNotificationManager()
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: makeSettings(),
            keepAwakeService: RecordingKeepAwakeService(),
            notificationManager: notificationManager,
            adapterFactory: { _ in InterruptedTokenAdapter() }
        )
        let conversationId = "conversation-interrupted-notification"
        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: executable.workingDirectory.path,
            permissionMode: nil,
            model: nil,
            effort: nil,
            initialPrompt: nil
        )

        defer {
            Task {
                await manager.kill(conversationId: conversationId)
            }
        }

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await manager.sendMessage("stop this", conversationId: conversationId)

        try await waitUntil("expected interrupted stop notification without trailing error notification") {
            manager.status(for: conversationId) == .idle &&
                notificationManager.handleEventCalls.count == 1
        }

        let recordedEvent = try XCTUnwrap(notificationManager.handleEventCalls.first)
        XCTAssertEqual(recordedEvent.conversationId, conversationId)
        XCTAssertEqual(recordedEvent.event, .stop(message: ConversationInterruption.displayMessage))
    }

    private func liveBashApprovalRequest(
        conversationId: String,
        toolUseId: String,
        command: String
    ) -> ClaudeDeferredToolRequest {
        ClaudeDeferredToolRequest(
            conversationId: conversationId,
            launchToken: "token",
            request: ToolApprovalRequest(
                sessionId: "session-deferred",
                toolUseId: toolUseId,
                toolName: "Bash",
                toolInput: #"{"command":"\#(command)"}"#
            )
        )
    }

    private func liveApprovalNotificationFixture() throws -> LiveApprovalNotificationFixture {
        let executable = try TempHookServerDeferredToolExecutable()
        let notificationManager = RecordingNotificationManager()
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            notificationManager: notificationManager,
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )

        return LiveApprovalNotificationFixture(
            executable: executable,
            notificationManager: notificationManager,
            hookServer: hookServer,
            manager: manager,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        )
    }
}

private struct LiveApprovalNotificationFixture {
    let executable: TempHookServerDeferredToolExecutable
    let notificationManager: RecordingNotificationManager
    let hookServer: StubClaudeHookServer
    let manager: DefaultAgentsManager
    let config: AgentSpawnConfig
}

private final class InterruptedTokenAdapter: AgentAdapter, @unchecked Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    func buildArgs(config: AgentConfig) -> [String] {
        []
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        guard json["type"] as? String == "interrupted" else {
            return []
        }

        return [
            .stop(message: ConversationInterruption.displayMessage),
            .tokens(
                input: 1,
                output: 0,
                cacheRead: 0,
                isError: true,
                stopReason: ConversationInterruption.requestInterruptedByUserReason,
                durationMs: 5,
                costUsd: 0,
                permissionDenials: []
            )
        ]
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let payload: [String: Any] = ["type": "interrupted"]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try stdin.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
    }

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        nil
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        false
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        SessionLaunchDecision(args: [], continuity: .preserved)
    }
}
