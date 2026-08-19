import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// Covers `idleAgentCLIKitActivitySignal`'s rule that a settled `.error` outranks a runtime that
/// still reports an active turn, together with the paths that must keep clearing it so the
/// conversation cannot wedge red.
@MainActor
extension AgentsManagerTests {
    func testStaleActiveRuntimeStatusDoesNotOverwriteSettledError() async throws {
        let fixture = makeAgentCLIKitFixture(
            adapter: StaleActiveTurnAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        )
        let manager = fixture.manager
        let conversationId = "agentclikit-settled-error-survives-stale-active-turn"
        let runtimeConversationId = AgentCLIKit.AgentConversationID(rawValue: conversationId)

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("boom", conversationId: conversationId)

        try await waitUntil("expected the provider error diagnostic to settle the status") {
            manager.status(for: conversationId) == .error
        }

        // The provider keeps its turn open — a bare error diagnostic never clears `isTurnActive` —
        // and the trailing tool-use row publishes a status past the terminal event index, so
        // index-based staleness no longer suppresses it. That publish is what used to re-arm
        // `.busy`, fast enough that the wait above never even saw `.error`.
        try await waitUntil("expected a runtime status published past the settled error row") {
            guard let terminalIndex = await manager.eventBuffers[conversationId]?.latestTerminalRuntimeEventIndex,
                  let status = await fixture.runtime.status(conversationId: runtimeConversationId) else {
                return false
            }
            return status.isTurnActive && status.lastEventIndex > terminalIndex
        }
        XCTAssertEqual(manager.status(for: conversationId), .error)

        let refreshed = await manager.refreshStatus(conversationId: conversationId)
        XCTAssertEqual(refreshed, .error)
        XCTAssertEqual(manager.status(for: conversationId), .error)

        await manager.kill(conversationId: conversationId)
    }

    func testSettledErrorClearsOnNextSend() async throws {
        let manager = makeAgentCLIKitFixture(
            adapter: StaleActiveTurnAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-settled-error-clears-on-send"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("boom", conversationId: conversationId)
        try await waitUntil("expected the provider error diagnostic to settle the status") {
            manager.status(for: conversationId) == .error
        }

        try await manager.sendMessage("quiet", conversationId: conversationId)
        XCTAssertEqual(manager.status(for: conversationId), .busy)

        await manager.kill(conversationId: conversationId)
    }

    func testSettledErrorClearsWhenAnExistingSessionGoalStarts() async throws {
        let manager = makeAgentCLIKitFixture(
            adapter: GoalInputWritingAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-settled-error-clears-on-goal-start"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        // A goal start writes no status of its own, so a previous turn's settled error would
        // otherwise outrank the turn it marks active.
        manager.updateStatus(.error, for: conversationId)
        try await manager.startGoal("Audit the failing turn", conversationId: conversationId)

        try await waitUntil("expected the goal start to supersede the settled error") {
            manager.status(for: conversationId) == .busy
        }

        await manager.kill(conversationId: conversationId)
    }

    func testSettledErrorClearsOnNextTerminalTokenRow() async throws {
        let manager = makeAgentCLIKitFixture(
            adapter: StaleActiveTurnAgentCLIKitAdapter(),
            detectedPath: "/bin/sh",
            basePath: "/usr/bin:/bin"
        ).manager
        let conversationId = "agentclikit-settled-error-clears-on-terminal-token"

        try await manager.spawn(id: conversationId, config: spawnConfig(workingDirectory: FileManager.default.temporaryDirectory.path))
        try await waitUntil("expected AgentCLIKit runtime to settle idle") {
            manager.status(for: conversationId) == .idle
        }

        try await manager.sendMessage("boom", conversationId: conversationId)
        try await waitUntil("expected the provider error diagnostic to settle the status") {
            manager.status(for: conversationId) == .error
        }

        let maybeGeneration = await manager.eventBuffers[conversationId]?.generation
        let generation = try XCTUnwrap(maybeGeneration)
        await manager.handleStreamEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 0,
                costUsd: nil,
                permissionDenials: [],
                isTerminal: true
            ),
            conversationId: conversationId,
            generation: generation,
            providerId: "claude"
        )
        XCTAssertEqual(manager.status(for: conversationId), .idle)

        await manager.kill(conversationId: conversationId)
    }
}

/// Emits a bare `severity: .error` diagnostic followed by a non-terminal tool-use usage row, so the
/// runtime keeps publishing `running` + `isTurnActive` after Alveary has already settled `.error`.
/// `TurnStatusAgentCLIKitAdapter` cannot stand in: every one of its rows either ends the turn or
/// needs a fresh host send, and a send re-arms `.busy` on its own.
struct StaleActiveTurnAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
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
                  if [ "$line" = "boom" ]; then
                    printf 'diag:Connection dropped (ECONNRESET)\\n'
                    printf 'usage:tool_use\\n'
                  fi
                done
                """
            ],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        if let message = line.removingPrefix("diag:") {
            return [.diagnostic(AgentCLIKit.AgentDiagnosticEvent(severity: .error, message: message))]
        }
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

/// Writes its goal start over stdin the way Claude does, so the runtime marks a turn active.
/// `GoalStartingAgentCLIKitAdapter` implements `startGoal` natively instead and marks no turn,
/// which is why that fixture's test asserts the status stays away from `.busy`.
struct GoalInputWritingAgentCLIKitAdapter: AgentCLIKit.AgentProviderAdapter {
    let definition = AgentCLIKit.AgentProviderDefinition(
        id: .claude,
        displayName: "Claude",
        executableNames: ["claude"],
        capabilities: AgentCLIKit.AgentProviderCapabilities(
            supportsGoalMode: true,
            supportsExistingSessionGoalStart: true
        )
    )

    func makeLaunchConfiguration(
        spawnConfig: AgentCLIKit.AgentSpawnConfig,
        resumedSession: AgentCLIKit.AgentSessionRecord?
    ) async throws -> AgentCLIKit.AgentLaunchConfiguration {
        AgentCLIKit.AgentLaunchConfiguration(
            executable: "/bin/sh",
            arguments: ["-c", "while IFS= read -r line; do :; done"],
            includesSpawnArguments: true
        )
    }

    func decodeStdoutLine(_ line: String) async throws -> [AgentCLIKit.AgentEvent] {
        []
    }

    func encodeInput(_ input: AgentCLIKit.AgentInput) async throws -> Data {
        Data()
    }

    func encodeGoalStart(
        _ objective: String,
        context: AgentCLIKit.AgentProviderGoalStartContext
    ) async throws -> AgentCLIKit.AgentProviderEncodedGoalStart? {
        AgentCLIKit.AgentProviderEncodedGoalStart(
            data: Data(("/goal " + objective + "\n").utf8),
            marksTurnActive: true
        )
    }
}
