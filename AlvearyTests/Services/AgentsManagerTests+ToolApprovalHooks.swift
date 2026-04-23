import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testResolveToolApprovalStopsExistingRuntimeBeforeResumeSpawn() async throws {
        let fixture = try makeApprovalFixture(
            conversationId: "conversation-hook-approval-resume",
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        defer { fixture.cleanup() }

        try await fixture.start()
        _ = try await fixture.manager.resolveToolApproval(
            conversationId: fixture.conversationId,
            approval: bashApprovalRequest(command: "swift test"),
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            sessionApproval: nil,
            config: fixture.config
        )

        try await waitUntil("expected resumed launch") {
            try fixture.executable.recordedLaunchArguments().count == 2
        }
        let decisions = await fixture.hookServer.decisions()
        XCTAssertEqual(decisions.first?.0, .allow)
        XCTAssertEqual(
            decisions.first?.1,
            ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
        )
    }

    func testResolveToolApprovalRecordsSessionApprovalBeforeResumeSpawn() async throws {
        let conversationId = "conversation-hook-session-approval"
        let fixture = try makeApprovalFixture(
            conversationId: conversationId,
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        defer { fixture.cleanup() }

        try await fixture.start(description: "expected initial launch before session approval resume")
        let sessionApproval = AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: conversationId,
            sessionId: "session-123",
            matchKind: .bashCommandGroup,
            matchValue: "git add"
        )
        _ = try await fixture.manager.resolveToolApproval(
            conversationId: conversationId,
            approval: bashApprovalRequest(command: "git add foo.swift"),
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            sessionApproval: sessionApproval,
            config: fixture.config
        )

        let sessionApprovals = await fixture.hookServer.sessionApprovals()
        XCTAssertEqual(sessionApprovals, [sessionApproval])
    }

    func testResolveToolApprovalInvalidatesOldHookTokenBeforeResumeSpawn() async throws {
        let fixture = try makeTokenRotationFixture()
        defer { fixture.cleanup() }

        try await fixture.manager.spawn(id: fixture.conversationId, config: fixture.config, forkSession: false)
        try await waitUntil("expected initial launch before approval resume") {
            try fixture.executable.recordedLaunchArguments().count == 1
        }

        _ = try await fixture.manager.resolveToolApproval(
            conversationId: fixture.conversationId,
            approval: bashApprovalRequest(command: "swift test"),
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            sessionApproval: nil,
            config: fixture.config
        )

        try await waitUntil("expected old hook token invalidation before resume") {
            await fixture.hookServer.invalidations().contains("old-token")
        }
        try await waitUntil("expected resumed launch after token invalidation") {
            try fixture.executable.recordedLaunchArguments().count == 2
        }

        let events = await fixture.hookServer.events()
        XCTAssertEqual(
            Array(events.prefix(2)),
            [
                .invalidateToken("old-token"),
                .recordDecision(
                    ClaudeToolApprovalResolution(decision: .allow),
                    ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")
                )
            ]
        )
    }

    func testResolveToolApprovalDiscardsDecisionWhenResumeSpawnFails() async throws {
        let conversationId = "conversation-hook-approval-spawn-failure"
        let sessionApproval = AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: conversationId,
            sessionId: "session-123",
            matchKind: .bashCommandGroup,
            matchValue: "swift test"
        )
        let fixture = try makeApprovalFixture(
            conversationId: conversationId,
            launchConfig: ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "approval-token"]
            )
        )
        defer { fixture.cleanup() }

        try await fixture.start(description: "expected initial launch before failed approval resume")
        let missingDirectory = fixture.executable.workingDirectory
            .appendingPathComponent("missing", isDirectory: true)
            .path

        do {
            _ = try await fixture.manager.resolveToolApproval(
                conversationId: conversationId,
                approval: bashApprovalRequest(command: "swift test"),
                resolution: ClaudeToolApprovalResolution(decision: .allow),
                sessionApproval: sessionApproval,
                config: hookSpawnConfig(workingDirectory: missingDirectory)
            )
            XCTFail("Expected approval resume spawn to fail")
        } catch {}

        let discards = await fixture.hookServer.discards()
        XCTAssertEqual(discards, [ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")])
        let discardedSessionApprovals = await fixture.hookServer.discardedSessionApprovals()
        XCTAssertEqual(discardedSessionApprovals, [sessionApproval])
    }

    func testResolveToolApprovalDiscardsDecisionWhenResumeSpawnsWithoutHookSettings() async throws {
        let executable = try TempExecutable()
        let sessionApproval = AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: "conversation-hook-approval-hookless-resume",
            sessionId: "session-123",
            matchKind: .bashCommandGroup,
            matchValue: "swift test"
        )
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
        let config = hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        defer {
            executable.cleanup()
            Task { await manager.kill(conversationId: conversationId) }
        }

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await waitUntil("expected initial launch before hookless approval resume") {
            try executable.recordedLaunchArguments().count == 1
        }

        _ = try await manager.resolveToolApproval(
            conversationId: conversationId,
            approval: bashApprovalRequest(command: "swift test"),
            resolution: ClaudeToolApprovalResolution(decision: .allow),
            sessionApproval: sessionApproval,
            config: config
        )

        try await waitUntil("expected hookless approval resume launch") {
            try executable.recordedLaunchArguments().count == 2
        }
        let discards = await hookServer.discards()
        XCTAssertEqual(discards, [ClaudeToolApprovalKey(sessionId: "session-123", toolUseId: "tool-1")])
        let discardedSessionApprovals = await hookServer.discardedSessionApprovals()
        XCTAssertEqual(discardedSessionApprovals, [sessionApproval])
    }
}

@MainActor
private extension AgentsManagerTests {
    struct ApprovalFixture {
        let executable: TempExecutable
        let hookServer: StubClaudeHookServer
        let manager: DefaultAgentsManager
        let conversationId: String
        let config: AgentSpawnConfig

        func start(description: String = "expected initial launch") async throws {
            try await manager.spawn(id: conversationId, config: config, forkSession: false)
            try await waitUntil(description) {
                try executable.recordedLaunchArguments().count == 1
            }
        }

        func cleanup() {
            executable.cleanup()
            Task { await manager.kill(conversationId: conversationId) }
        }
    }

    func makeTokenRotationFixture() throws -> ApprovalFixture {
        let launchConfigs = [
            ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "old-token"]
            ),
            ClaudeHookLaunchConfig(
                arguments: [],
                environment: ["ALVEARY_HOOK_TOKEN": "new-token"]
            )
        ]
        return try makeApprovalFixture(
            conversationId: "conversation-hook-token-resume",
            launchConfigs: launchConfigs
        )
    }

    func makeApprovalFixture(
        conversationId: String,
        launchConfig: ClaudeHookLaunchConfig
    ) throws -> ApprovalFixture {
        try makeApprovalFixture(conversationId: conversationId, launchConfigs: [launchConfig])
    }

    func makeApprovalFixture(
        conversationId: String,
        launchConfigs: [ClaudeHookLaunchConfig?]
    ) throws -> ApprovalFixture {
        let executable = try TempExecutable()
        let hookServer = StubClaudeHookServer(launchConfigs: launchConfigs)
        let manager = makeTestManager(
            settings: makeSettings(cliPath: executable.url.path),
            claudeHookServer: hookServer,
            adapterFactory: { _ in RecordingLaunchAdapter() }
        )
        return ApprovalFixture(
            executable: executable,
            hookServer: hookServer,
            manager: manager,
            conversationId: conversationId,
            config: hookSpawnConfig(workingDirectory: executable.workingDirectory.path)
        )
    }

    func bashApprovalRequest(command: String) -> ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"\(command)\"}"
        )
    }
}
