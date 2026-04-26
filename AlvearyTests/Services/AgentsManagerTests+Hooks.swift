import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testClaudeSpawnAddsHookSettingsWhenHookServerStarts() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: ["--settings", "/tmp/alveary-hooks.json"],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-settings"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        try await waitUntil("expected launch arguments with hook settings") {
            try executable.recordedLaunchArguments().count == 1
        }

        let args = try XCTUnwrap(executable.recordedLaunchArguments().first)
        XCTAssertTrue(args.contains("--settings"))
        XCTAssertTrue(args.contains("/tmp/alveary-hooks.json"))
    }

    func testClaudeSpawnFallsBackWithoutHookSettingsWhenHookServerCannotStart() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: StubClaudeHookServer(launchConfig: nil),
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-fallback"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        try await waitUntil("expected launch arguments without hook settings") {
            try executable.recordedLaunchArguments().count == 1
        }

        let args = try XCTUnwrap(executable.recordedLaunchArguments().first)
        XCTAssertFalse(args.contains("--settings"))
    }

    func testClaudeSpawnInvalidatesHookTokenWhenProcessExits() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token-to-invalidate"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-token-exit"

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected launch before token invalidation") {
            try executable.recordedLaunchArguments().count == 1
        }

        await manager.kill(conversationId: conversationId)

        try await waitUntil("expected hook token invalidation") {
            await hookServer.invalidations() == ["token-to-invalidate"]
        }
    }

    func testClaudeKillRemovesSessionApprovalsForConversationSession() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token-to-invalidate"]
            )
        )
        let sessionManager = InMemorySessionManager()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            sessionManager: sessionManager,
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-cleanup"

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected launch before session approval cleanup") {
            try executable.recordedLaunchArguments().count == 1
        }

        let sessionId = await sessionManager.sessionId(for: conversationId)
        await manager.kill(conversationId: conversationId)

        try await waitUntil("expected conversation-scoped session approval cleanup") {
            let removedSessionApprovals = await hookServer.removedSessionApprovalIDs()
            guard removedSessionApprovals.count == 1 else {
                return false
            }
            return removedSessionApprovals[0].conversationId == conversationId &&
                removedSessionApprovals[0].sessionId == sessionId
        }
    }

    func testClaudeStreamPermissionModeChangeUpdatesHookServerConversationMode() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in PermissionModeEchoAgentAdapter() }
        )
        let conversationId = "conversation-hook-permission-mode"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        try await manager.sendMessage("plan", conversationId: conversationId)

        try await waitUntil("expected hook server permission-mode update event") {
            await hookServer.events().contains(
                .updatePermissionMode(permissionMode: "plan", conversationId: conversationId)
            )
        }
    }

    func testClaudeToolDeferredStopsCurrentRuntimeButPreservesSession() async throws {
        let executable = try TempDeferredToolExecutable()
        defer { executable.cleanup() }
        let sessionManager = InMemorySessionManager()
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            sessionManager: sessionManager,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-hook-tool-deferred-stop"

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        try await waitUntil("expected manager to stop the deferred runtime") {
            let isRunning = await manager.isRunning(conversationId: conversationId)
            let status = manager.status(for: conversationId)
            return !isRunning && status == .stopped
        }

        let hasSession = await sessionManager.hasSession(for: conversationId)
        XCTAssertTrue(hasSession)
    }

    func testClaudeToolDeferredDropsTrailingEventsFromSameRuntime() async throws {
        let executable = try TempDeferredToolExecutable(emitsTrailingAssistantMessage: true)
        defer { executable.cleanup() }
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-hook-tool-deferred-drop-trailing-events"

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        guard let subscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            return XCTFail("Expected live event subscription")
        }
        async let events = collectedEvents(from: subscription.stream)

        try await waitUntil("expected manager to stop the deferred runtime") {
            let isRunning = await manager.isRunning(conversationId: conversationId)
            return !isRunning
        }

        let collected = await events

        XCTAssertTrue(collected.contains { event in
            if case .toolApprovalRequested(let request) = event {
                return request.toolName == "AskUserQuestion"
            }
            return false
        })
        XCTAssertTrue(collected.contains { event in
            if case .tokens(_, _, _, _, let stopReason, _, _, _) = event {
                return stopReason == "tool_deferred"
            }
            return false
        })
        XCTAssertFalse(collected.contains { event in
            if case .message(role: "assistant", content: let content, parentToolUseId: _) = event {
                return content.contains("returning internal errors")
            }
            return false
        })
    }

    func testClaudeHookDeferredToolAttachmentStopsCurrentRuntimeAndDropsTrailingEvents() async throws {
        let executable = try TempDeferredToolExecutable(
            eventStyle: .hookAttachment,
            emitsTrailingAssistantMessage: true,
            trailingDelaySeconds: 0
        )
        defer { executable.cleanup() }
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-hook-deferred-attachment-drop-trailing-events"

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )

        guard let subscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0) else {
            return XCTFail("Expected live event subscription")
        }
        async let events = collectedEvents(from: subscription.stream)

        try await waitUntil("expected manager to stop the deferred runtime") {
            let isRunning = await manager.isRunning(conversationId: conversationId)
            let status = manager.status(for: conversationId)
            return !isRunning && status == .stopped
        }

        let collected = await events

        XCTAssertTrue(collected.contains { event in
            if case .toolApprovalRequested(let request) = event {
                return request.toolName == "AskUserQuestion"
            }
            return false
        })
        XCTAssertTrue(collected.contains { event in
            if case .tokens(_, _, _, _, let stopReason, _, _, _) = event {
                return stopReason == "tool_deferred"
            }
            return false
        })
        XCTAssertFalse(collected.contains { event in
            if case .message(role: "assistant", content: let content, parentToolUseId: _) = event {
                return content.contains("returning internal errors")
            }
            return false
        })
    }

    func testClaudeHookServerDeferredToolKeepsRuntimeAliveForLaterStdoutEventsFromHookServer() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        let collected = try await collectHookServerDeferredToolRaceEvents(fixture)
        assertHookServerLiveDeferredToolRaceEvents(collected)
    }

    func testClaudeHookServerDeferredToolIgnoresStaleLaunchToken() async throws {
        let fixture = try hookServerDeferredToolRaceFixture()
        defer { cleanupHookServerDeferredToolRaceFixture(fixture) }

        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected first tool call before stale hook deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }

        await emitHookServerDeferredToolRequest(fixture, launchToken: "stale-token")
        try await Task.sleep(for: .milliseconds(100))

        let isRunning = await fixture.manager.isRunning(conversationId: fixture.conversationId)
        let retainedEventCount = await fixture.manager.retainedEventCount(conversationId: fixture.conversationId)
        XCTAssertTrue(isRunning)
        XCTAssertEqual(retainedEventCount, 1)
    }

    func hookSpawnConfig(workingDirectory: String) -> AgentSpawnConfig {
        AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: workingDirectory,
            permissionMode: "default",
            model: nil,
            effort: nil,
            initialPrompt: nil
        )
    }
}

@MainActor
extension AgentsManagerTests {
    struct HookServerDeferredToolRaceFixture {
        let executable: TempHookServerDeferredToolExecutable
        let hookServer: StubClaudeHookServer
        let manager: DefaultAgentsManager
        let conversationId: String
    }

    func hookServerDeferredToolRaceFixture() throws -> HookServerDeferredToolRaceFixture {
        let executable = try TempHookServerDeferredToolExecutable()
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in ClaudeAdapter() }
        )
        let conversationId = "conversation-hook-server-deferred-tool-stop"

        return HookServerDeferredToolRaceFixture(
            executable: executable,
            hookServer: hookServer,
            manager: manager,
            conversationId: conversationId
        )
    }

    func cleanupHookServerDeferredToolRaceFixture(_ fixture: HookServerDeferredToolRaceFixture) {
        fixture.executable.cleanup()
        Task { await fixture.manager.kill(conversationId: fixture.conversationId) }
    }

    func collectHookServerDeferredToolRaceEvents(_ fixture: HookServerDeferredToolRaceFixture) async throws -> [ConversationEvent] {
        try await fixture.manager.spawn(
            id: fixture.conversationId,
            config: hookSpawnConfig(workingDirectory: fixture.executable.workingDirectory.path),
            forkSession: false
        )
        guard let subscription = await fixture.manager.subscribe(
            conversationId: fixture.conversationId,
            afterIndex: 0
        ) else {
            XCTFail("Expected live event subscription")
            return []
        }
        async let events = collectedEvents(from: subscription.stream)

        try await waitUntil("expected first tool call before hook deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 1
        }
        await emitHookServerDeferredToolRequest(fixture, launchToken: "token")

        try await waitUntil("expected manager to keep accepting live events after hook server deferral") {
            await fixture.manager.retainedEventCount(conversationId: fixture.conversationId) >= 3
        }
        await fixture.manager.kill(conversationId: fixture.conversationId)

        return await events
    }

    func emitHookServerDeferredToolRequest(
        _ fixture: HookServerDeferredToolRaceFixture,
        launchToken: String
    ) async {
        await emitHookServerDeferredToolRequest(
            fixture,
            toolUseId: "toolu_first",
            command: "date +%s",
            launchToken: launchToken
        )
    }

    func emitHookServerDeferredToolRequest(
        _ fixture: HookServerDeferredToolRaceFixture,
        toolUseId: String,
        command: String,
        launchToken: String
    ) async {
        await fixture.hookServer.emitDeferredToolRequest(
            ClaudeDeferredToolRequest(
                conversationId: fixture.conversationId,
                launchToken: launchToken,
                request: ToolApprovalRequest(
                    sessionId: "session-deferred",
                    toolUseId: toolUseId,
                    toolName: "Bash",
                    toolInput: #"{"command":"\#(command)"}"#
                )
            )
        )
    }

    func assertHookServerDeferredToolRaceEvents(_ collected: [ConversationEvent]) {
        XCTAssertTrue(collected.contains { event in
            if case .toolApprovalRequested(let request) = event {
                return request.toolUseId == "toolu_first"
            }
            return false
        })
        XCTAssertTrue(collected.contains { event in
            if case .tokens(_, _, _, _, let stopReason, _, _, _) = event {
                return stopReason == "tool_deferred"
            }
            return false
        })
        XCTAssertFalse(collected.contains { event in
            if case .toolCall(id: "toolu_second", name: _, input: _, parentToolUseId: _, callerAgent: _) = event {
                return true
            }
            return false
        })
        XCTAssertFalse(collected.contains { event in
            if case .message(role: "assistant", content: let content, parentToolUseId: _) = event {
                return content.contains("returning internal errors")
            }
            return false
        })
    }

    func assertHookServerLiveDeferredToolRaceEvents(_ collected: [ConversationEvent]) {
        XCTAssertTrue(collected.contains { event in
            if case .toolApprovalRequested(let request) = event {
                return request.toolUseId == "toolu_first"
            }
            return false
        })
        XCTAssertTrue(collected.contains { event in
            if case .toolCall(id: "toolu_second", name: _, input: _, parentToolUseId: _, callerAgent: _) = event {
                return true
            }
            return false
        })
    }
}
