import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
    func testDestroyRuntimePreservingStateRetainsCanonicalConversationState() async throws {
        let manager = makeAgentCLIKitFixture(
            adapter: ResolvingAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationID = "preserved-runtime-state"
        let originalState = manager.conversationState(for: conversationID)
        originalState.inputDraft = "Keep this draft"

        try await manager.destroyRuntimePreservingState(conversationId: conversationID)

        let retainedState = manager.conversationState(for: conversationID)
        XCTAssertIdentical(retainedState, originalState)
        XCTAssertEqual(retainedState.inputDraft, "Keep this draft")
    }

    func testAgentCLIKitSpawnRefreshesRuntimeStatusBeforeReturning() async throws {
        let executable = try makeScript(named: "running-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-immediate-running-status"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))

        let isRunning = await manager.isRunning(conversationId: conversationId)
        XCTAssertTrue(isRunning)
        do {
            try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
            XCTFail("Expected duplicate AgentCLIKit spawn to fail")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertTrue(message.contains("Agent already running"))
        } catch {
            XCTFail("Expected spawnFailed, got \(error)")
        }
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitConcurrentSpawnAllowsOnlyOneLaunch() async throws {
        let executable = try makeScript(named: "concurrent-running-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-concurrent-spawn"
        let config = spawnConfig(workingDirectory: executable.deletingLastPathComponent().path)

        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try await manager.spawn(id: conversationId, config: config)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var values: [Bool] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(results.filter { !$0 }.count, 1)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitReconfigureDuringSpawnIsRejected() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DelayedInitialLaunchAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-reconfigure-during-spawn"
        let config = spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        let spawnTask = Task {
            try await manager.spawn(id: conversationId, config: config)
        }

        try await waitUntil("expected AgentCLIKit spawn to be in progress") {
            await manager.isRunning(conversationId: conversationId)
        }
        do {
            try await manager.reconfigureSession(conversationId: conversationId, config: config)
            XCTFail("Expected reconfigure during spawn to fail")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertTrue(message.contains("Spawn already in progress"))
        } catch {
            XCTFail("Expected spawnFailed, got \(error)")
        }

        try await spawnTask.value
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitFreshSessionDuringSpawnIsRejected() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: DelayedInitialLaunchAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-fresh-session-during-spawn"
        let config = spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path)
        let spawnTask = Task {
            try await manager.spawn(id: conversationId, config: config)
        }

        try await waitUntil("expected AgentCLIKit spawn to be in progress") {
            await manager.isRunning(conversationId: conversationId)
        }
        do {
            try await manager.startFreshSession(conversationId: conversationId, config: config)
            XCTFail("Expected fresh session during spawn to fail")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertTrue(message.contains("Spawn already in progress"))
        } catch {
            XCTFail("Expected spawnFailed, got \(error)")
        }

        try await spawnTask.value
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitRunningWithoutActiveTurnStaysIdle() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-idle-runtime-status"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }

        XCTAssertEqual(manager.status(for: conversationId), .idle)
        await manager.kill(conversationId: conversationId)
    }

    func testRefreshStatusPublishesAgentStatusChangedWhenCachedSignalChanges() async throws {
        let executable = try makeScript(named: "refresh-idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-refresh-status-posts"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        let expectation = expectation(description: "idle status notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?["conversationId"] as? String == conversationId,
                  notification.userInfo?["signal"] as? ActivitySignal == .idle else {
                return
            }
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.updateStatus(.busy, for: conversationId)
        let refreshedStatus = await manager.refreshStatus(conversationId: conversationId)

        XCTAssertEqual(refreshedStatus, .idle)
        await fulfillment(of: [expectation], timeout: 1)
        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitActiveTurnStatusControlsBusyState() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: TurnStatusAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-active-turn-status"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("start", conversationId: conversationId)
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)
        try await waitUntil("expected AgentCLIKit tool-use usage to keep turn active") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return status.lastEventIndex >= 2 && status.isTurnActive
        }
        try await waitUntil("expected AgentCLIKit active turn to map to busy") {
            manager.status(for: conversationId) == .busy
        }

        try await manager.sendMessage("finish", conversationId: conversationId)
        try await waitUntil("expected AgentCLIKit runtime to report inactive turn") {
            guard let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return status.lastEventIndex >= 3 && !status.isTurnActive
        }
        try await waitUntil("expected AgentCLIKit terminal usage to map to idle") {
            await manager.refreshStatus(conversationId: conversationId) == .idle
        }

        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitCancelRefreshesCachedRunningStatus() async throws {
        let executable = try makeScript(named: "cancel-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let fixture = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-cancel-refreshes-status"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }

        await manager.cancelTurn(conversationId: conversationId)

        try await waitUntil("expected AgentCLIKit cancellation to publish stopped status") {
            guard let runtimeStatus = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            let isManagerRunning = await manager.isRunning(conversationId: conversationId)
            return runtimeStatus.state == .cancelled &&
                !runtimeStatus.isProcessRunning &&
                !isManagerRunning &&
                manager.status(for: conversationId) == .idle
        }

        await manager.kill(conversationId: conversationId)
    }

    func testAgentCLIKitSendAfterKillIsRejected() async throws {
        let executable = try makeScript(named: "slow-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-send-after-kill"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to be running") {
            await manager.isRunning(conversationId: conversationId)
        }

        await manager.kill(conversationId: conversationId)

        do {
            try await manager.sendMessage("after close", conversationId: conversationId)
            XCTFail("Expected send after kill to fail")
        } catch AgentError.stdinClosed {
            XCTAssertNotEqual(manager.status(for: conversationId), .busy)
        } catch {
            XCTFail("Expected stdinClosed, got \(error)")
        }
    }

    func testRuntimeActivityMapsActivityStateIntoStatus() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-runtime-activity-status-mapping"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        let busyNotification = expectation(description: "busy status notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?["conversationId"] as? String == conversationId,
                  notification.userInfo?["signal"] as? ActivitySignal == .busy else {
                return
            }
            busyNotification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await manager.handleStreamEvent(
            .runtimeActivity(state: .active, turnId: "turn-1", outcome: .unknown),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .busy)
        await fulfillment(of: [busyNotification], timeout: 1)

        await manager.handleStreamEvent(
            .runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .idle)

        await manager.kill(conversationId: conversationId)
    }

    func testRuntimeActivityFailureMapsToErrorAndIdlePreservesIt() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-runtime-activity-failure-status"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)

        await manager.handleStreamEvent(
            .runtimeActivity(state: .idle, turnId: "turn-1", outcome: .failed(message: "Codex turn failed.")),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .error)

        // Idle activity only releases a busy status; it must not clear an error.
        await manager.handleStreamEvent(
            .runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .error)

        await manager.kill(conversationId: conversationId)
    }

    func testRuntimeActivityDoesNotOverwriteWaitingForUserStatus() async throws {
        let executable = try makeScript(named: "idle-agent", body: "sleep 5\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let manager = makeAgentCLIKitFixture(
            adapter: PathResolvingAgentCLIKitAdapter(executableName: executable.lastPathComponent),
            detectedPath: executable.path,
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-runtime-activity-preserves-waiting"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: executable.deletingLastPathComponent().path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }
        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)
        let approval = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )

        await manager.handleStreamEvent(
            .toolApprovalRequested(approval),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .waitingForUser)

        // Parallel tool activity must not flip a waiting conversation back to busy.
        await manager.handleStreamEvent(
            .runtimeActivity(state: .active, turnId: "turn-1", outcome: .unknown),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .waitingForUser)

        await manager.handleStreamEvent(
            .runtimeActivity(state: .idle, turnId: nil, outcome: .failed(message: "Codex turn failed.")),
            conversationId: conversationId,
            generation: generation,
            providerId: "codex"
        )
        XCTAssertEqual(manager.status(for: conversationId), .waitingForUser)

        await manager.kill(conversationId: conversationId)
    }
}

struct TurnStatusAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
            arguments: [
                "-c",
                """
                while IFS= read -r line; do
                  if [ "$line" = "finish" ]; then
                    printf 'usage:end_turn\\n'
                  else
                    printf 'usage:tool_use\\n'
                  fi
                done
                """
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        guard let stopReason = line.removingPrefix("usage:") else {
            return []
        }
        return [.usage(AgentCLIKit.AgentUsageEvent(
            model: nil,
            inputTokens: nil,
            outputTokens: nil,
            stopReason: stopReason
        ))]
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        if case let .userMessage(message) = input {
            return Data((message.text + "\n").utf8)
        }
        return Data()
    }
}
