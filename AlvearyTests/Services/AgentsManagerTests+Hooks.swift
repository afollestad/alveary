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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
            settings: makeSettings(cliPath: executable.url.path),
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
