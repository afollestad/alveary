import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension AgentsManagerTests {
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
}

private struct TurnStatusAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
