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

    func testResolveToolApprovalStopsExistingRuntimeBeforeResumeSpawn() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(cliPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-approval-resume"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }
        let config = hookSpawnConfig(workingDirectory: executable.workingDirectory.path)

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await waitUntil("expected initial launch") {
            try executable.recordedLaunchArguments().count == 1
        }

        try await manager.resolveToolApproval(
            conversationId: conversationId,
            approval: ToolApprovalRequest(
                sessionId: "session-123",
                toolUseId: "tool-1",
                toolName: "Bash",
                toolInput: "{\"command\":\"swift test\"}"
            ),
            decision: .allow,
            config: config
        )

        try await waitUntil("expected resumed launch") {
            try executable.recordedLaunchArguments().count == 2
        }
        let decisions = await hookServer.decisions()
        XCTAssertEqual(decisions.first?.0, .allow)
        XCTAssertEqual(decisions.first?.1, ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1"))
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

    func testResolveToolApprovalInvalidatesOldHookTokenBeforeResumeSpawn() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfigs: [
                ClaudeHookLaunchConfig(
                    arguments: [],
                    environment: ["ALVEARY_HOOK_TOKEN": "old-token"]
                ),
                ClaudeHookLaunchConfig(
                    arguments: [],
                    environment: ["ALVEARY_HOOK_TOKEN": "new-token"]
                )
            ]
        )
        let manager = makeTestManager(
            settings: makeSettings(cliPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-token-resume"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }
        let config = hookSpawnConfig(workingDirectory: executable.workingDirectory.path)

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await waitUntil("expected initial launch before approval resume") {
            try executable.recordedLaunchArguments().count == 1
        }

        try await manager.resolveToolApproval(
            conversationId: conversationId,
            approval: ToolApprovalRequest(
                sessionId: "session-123",
                toolUseId: "tool-1",
                toolName: "Bash",
                toolInput: "{\"command\":\"swift test\"}"
            ),
            decision: .allow,
            config: config
        )

        try await waitUntil("expected old hook token invalidation before resume") {
            await hookServer.invalidations().contains("old-token")
        }
        try await waitUntil("expected resumed launch after token invalidation") {
            try executable.recordedLaunchArguments().count == 2
        }
        await assertOldHookTokenInvalidatedBeforeApprovalDecision(hookServer)
    }

    func testResolveToolApprovalDiscardsDecisionWhenResumeSpawnFails() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        let manager = makeTestManager(
            settings: makeSettings(cliPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-approval-spawn-failure"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )

        try await manager.spawn(
            id: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path),
            forkSession: false
        )
        try await waitUntil("expected initial launch before failed approval resume") {
            try executable.recordedLaunchArguments().count == 1
        }

        let missingDirectory = executable.workingDirectory
            .appendingPathComponent("missing", isDirectory: true)
            .path
        do {
            try await manager.resolveToolApproval(
                conversationId: conversationId,
                approval: approval,
                decision: .allow,
                config: hookSpawnConfig(workingDirectory: missingDirectory)
            )
            XCTFail("Expected approval resume spawn to fail")
        } catch {}

        let discards = await hookServer.discards()
        XCTAssertEqual(discards, [ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")])
    }

    func testResolveToolApprovalDiscardsDecisionWhenResumeSpawnsWithoutHookSettings() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }
        let hookServer = StubClaudeHookServer(
            launchConfigs: [
                ClaudeHookLaunchConfig(
                    arguments: [],
                    environment: ["ALVEARY_HOOK_TOKEN": "old-token"]
                ),
                nil
            ]
        )
        let manager = makeTestManager(
            settings: makeSettings(cliPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        let conversationId = "conversation-hook-approval-hookless-resume"
        defer {
            Task { await manager.kill(conversationId: conversationId) }
        }
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        let config = hookSpawnConfig(workingDirectory: executable.workingDirectory.path)

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await waitUntil("expected initial launch before hookless approval resume") {
            try executable.recordedLaunchArguments().count == 1
        }

        try await manager.resolveToolApproval(
            conversationId: conversationId,
            approval: approval,
            decision: .allow,
            config: config
        )

        try await waitUntil("expected hookless approval resume launch") {
            try executable.recordedLaunchArguments().count == 2
        }
        let discards = await hookServer.discards()
        XCTAssertEqual(discards, [ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")])
    }

    private func hookSpawnConfig(workingDirectory: String) -> AgentSpawnConfig {
        AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: workingDirectory,
            permissionMode: "default",
            model: nil,
            effort: nil,
            initialPrompt: nil
        )
    }

    private func assertOldHookTokenInvalidatedBeforeApprovalDecision(_ hookServer: StubClaudeHookServer) async {
        let events = await hookServer.events()
        XCTAssertEqual(
            Array(events.prefix(2)),
            [
                .invalidateToken("old-token"),
                .recordDecision(.allow, ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1"))
            ]
        )
    }
}
