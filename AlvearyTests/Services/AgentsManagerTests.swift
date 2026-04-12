import Foundation
import XCTest

@testable import Alveary

@MainActor
final class AgentsManagerTests: XCTestCase {
    func testReconfigureSessionForksExistingSessionAndRebuildsArgsWithUpdatedPermissionModeAndEffort() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let adapter = RecordingLaunchAdapter()
        let manager = makeTestManager(
            settings: makeSettings(
                cliPath: executable.url.path,
                extraArgs: "--label \"value with spaces\" --mode fast"
            ),
            adapterFactory: { _ in adapter }
        )
        let conversationId = "conversation-reconfigure"
        let initialConfig = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: executable.workingDirectory.path,
            permissionMode: "plan",
            model: "sonnet",
            effort: "high",
            initialPrompt: nil
        )
        let updatedConfig = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: executable.workingDirectory.path,
            permissionMode: "acceptEdits",
            model: "opus",
            effort: "max",
            initialPrompt: nil
        )

        defer {
            Task {
                await manager.kill(conversationId: conversationId)
            }
        }

        try await manager.spawn(id: conversationId, config: initialConfig, forkSession: false)
        try await waitUntil("expected initial launch log entry before reconfigure") {
            let recordedLaunches = try executable.recordedLaunchArguments()
            return recordedLaunches.count == 1
        }

        try await manager.reconfigureSession(conversationId: conversationId, config: updatedConfig)

        let buildConfigs = adapter.recordedBuildConfigs
        XCTAssertEqual(buildConfigs.map(\.permissionMode), ["plan", "acceptEdits"])
        XCTAssertEqual(buildConfigs.map(\.model), ["sonnet", "opus"])
        XCTAssertEqual(buildConfigs.map(\.effort), ["high", "max"])

        let expectedExtraArgs = ["--label", "value with spaces", "--mode", "fast"]
        assertSessionLaunchCalls(adapter.recordedSessionLaunchCalls)
        try await assertRecordedLaunches(
            executable: executable,
            expectedExtraArgs: expectedExtraArgs
        )

        await manager.kill(conversationId: conversationId)
        try await assertManagerStopped(manager: manager, conversationId: conversationId)
    }

    func testSpawnSendMessageAndKillLifecycle() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let settings = InMemorySettingsService(
            current: AppSettings(providerConfigs: ["claude": ProviderCustomConfig(cli: executable.url.path)])
        )
        let sessionManager = InMemorySessionManager()
        let adapter = EchoAgentAdapter()
        let manager = DefaultAgentsManager(
            sessionManager: sessionManager,
            providerDetection: StubProviderDetectionService(),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: settings,
            notificationManager: StubNotificationManager(),
            adapterFactory: { _ in adapter }
        )
        let conversationId = "conversation-1"
        let config = AgentSpawnConfig(
            providerId: "claude",
            workingDirectory: FileManager.default.temporaryDirectory.path,
            permissionMode: nil,
            model: nil,
            effort: nil,
            initialPrompt: nil
        )

        try await manager.spawn(id: conversationId, config: config, forkSession: false)

        XCTAssertEqual(manager.status(for: conversationId), .idle)
        let hasSession = await sessionManager.hasSession(for: conversationId)
        XCTAssertTrue(hasSession)

        try await manager.sendMessage("hello", conversationId: conversationId)

        try await waitUntil("expected helper executable to receive stdin after sendMessage") {
            try executable.recordedInputLines().count == 1
        }

        let recordedInputLines = try executable.recordedInputLines()
        XCTAssertEqual(recordedInputLines.count, 1)
        XCTAssertTrue(recordedInputLines[0].contains("\"content\":\"hello\""))
        XCTAssertEqual(manager.status(for: conversationId), .busy)

        await manager.kill(conversationId: conversationId)

        try await waitUntil("expected spawned process teardown and session cleanup after kill") {
            let hasTrackedProcess = await manager.hasTrackedProcess(conversationId: conversationId)
            let isRunning = await manager.isRunning(conversationId: conversationId)
            let hasSession = await sessionManager.hasSession(for: conversationId)
            let subscription = await manager.subscribe(conversationId: conversationId, afterIndex: 0)
            return !hasTrackedProcess && !isRunning && !hasSession && subscription == nil
        }

        XCTAssertEqual(manager.status(for: conversationId), .neutral)
    }

    func testReadAgentOutputDecodesStructuredStdoutLine() async throws {
        let adapter = EchoAgentAdapter()
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: InMemorySettingsService(),
            notificationManager: StubNotificationManager(),
            adapterFactory: { _ in adapter }
        )
        let stdout = Pipe()
        let stderr = Pipe()
        let stream = manager.readAgentOutput(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            adapter: adapter
        )
        let payload: [String: String] = [
            "type": "message",
            "role": "assistant",
            "content": "hello"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let eventTask = Task {
            try await firstEvent(
                from: stream,
                description: "expected decoded stdout event"
            )
        }

        try stdout.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()

        let event = try await eventTask.value
        XCTAssertEqual(event, .message(role: "assistant", content: "echo:hello", parentToolUseId: nil))
        XCTAssertEqual(adapter.decodedPayloads.count, 1)
    }

    func testReadAgentOutputIncludesNewestStderrLinesAfterWrapAround() async throws {
        let adapter = EchoAgentAdapter()
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: InMemorySettingsService(),
            notificationManager: StubNotificationManager(),
            adapterFactory: { _ in adapter }
        )
        let stdout = Pipe()
        let stderr = Pipe()
        let stream = manager.readAgentOutput(
            stdout: stdout.fileHandleForReading,
            stderr: stderr.fileHandleForReading,
            adapter: adapter
        )

        let eventTask = Task {
            try await firstEvent(
                from: stream,
                description: "expected malformed stdout error event"
            )
        }

        for index in 0...20 {
            try stderr.fileHandleForWriting.write(contentsOf: Data("stderr-\(index)\n".utf8))
        }
        try stdout.fileHandleForWriting.write(contentsOf: Data("not-json\n".utf8))
        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()

        let event = try await eventTask.value
        guard case let .error(message) = event else {
            XCTFail("Expected .error event, got \(String(describing: event))")
            return
        }

        XCTAssertFalse(message.contains("stderr-0"))
        XCTAssertTrue(message.contains("stderr-1"))
        XCTAssertTrue(message.contains("stderr-20"))
    }

    private func assertSessionLaunchCalls(_ launchCalls: [RecordingLaunchAdapter.SessionLaunchCall]) {
        XCTAssertEqual(launchCalls.count, 2)
        XCTAssertEqual(launchCalls.map(\.isResuming), [false, true])
        XCTAssertEqual(launchCalls.map(\.forkSession), [false, true])
        XCTAssertEqual(launchCalls.first?.sessionId, launchCalls.last?.sessionId)
    }

    private func assertRecordedLaunches(
        executable: TempExecutable,
        expectedExtraArgs: [String]
    ) async throws {
        try await waitUntil("expected 2 complete launch log entries after reconfigure") {
            let recordedLaunches = try executable.recordedLaunchArguments()
            return recordedLaunches.count == 2 && recordedLaunches.allSatisfy { launchArgs in
                agentsManagerLaunchContainsSubsequence(launchArgs, expectedExtraArgs)
            }
        }

        let recordedLaunches = try executable.recordedLaunchArguments()
        XCTAssertEqual(recordedLaunches.count, 2)
        XCTAssertTrue(
            recordedLaunches.allSatisfy { launchArgs in
                agentsManagerLaunchContainsSubsequence(launchArgs, expectedExtraArgs)
            },
            "Expected every launch to include parsed extra args. Launches: \(recordedLaunches)"
        )
    }

    private func assertManagerStopped(
        manager: DefaultAgentsManager,
        conversationId: String
    ) async throws {
        try await waitUntil("expected reconfigured process teardown after kill") {
            let hasTrackedProcess = await manager.hasTrackedProcess(conversationId: conversationId)
            let isRunning = await manager.isRunning(conversationId: conversationId)
            return !hasTrackedProcess && !isRunning
        }
    }
}
