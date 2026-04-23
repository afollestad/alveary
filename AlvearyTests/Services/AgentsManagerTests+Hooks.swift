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
