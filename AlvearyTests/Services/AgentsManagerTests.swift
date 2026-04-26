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
                extraArgs: "--label \"value with spaces\" --mode fast"
            ),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
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
            current: AppSettings()
        )
        let sessionManager = InMemorySessionManager()
        let adapter = EchoAgentAdapter()
        let manager = DefaultAgentsManager(
            sessionManager: sessionManager,
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
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

    func testReadAgentOutputDecodesFinalStructuredStdoutLineWithoutTrailingNewline() async throws {
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
                description: "expected decoded stdout event without trailing newline"
            )
        }

        try stdout.fileHandleForWriting.write(contentsOf: data)
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

    func testDefaultAgentEnvironmentBuilderPreservesClaudeStreamWorkaroundEnvVars() {
        withEnvironmentValue(key: "CLAUDE_STREAM_IDLE_TIMEOUT_MS", value: "30000") {
            withEnvironmentValue(key: "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK", value: "1") {
                let environment = DefaultAgentEnvironmentBuilder().buildEnvironment()

                XCTAssertEqual(environment["CLAUDE_STREAM_IDLE_TIMEOUT_MS"], "30000")
                XCTAssertEqual(environment["CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK"], "1")
            }
        }
    }

    func testUnknownSlashCommandNotificationUsesErrorMessageInsteadOfSuccessTokens() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let notificationManager = RecordingNotificationManager()
        let manager = DefaultAgentsManager(
            sessionManager: InMemorySessionManager(),
            providerDetection: StubProviderDetectionService(resolvedPath: executable.url.path),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: makeSettings(),
            notificationManager: notificationManager,
            adapterFactory: { _ in
                SlashCommandTokenAdapter(
                    input: 0,
                    output: 0,
                    cacheRead: 0,
                    isError: false,
                    stopReason: nil,
                    durationMs: 5,
                    costUsd: 0,
                    permissionDenials: []
                )
            }
        )
        let conversationId = "conversation-slash-command-notification"
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

        let state = manager.conversationState(for: conversationId)
        state.grouper.appendLocalUserMessage(id: "user-1", text: "/test-command")

        try await manager.spawn(id: conversationId, config: config, forkSession: false)
        try await manager.sendMessage("/test-command", conversationId: conversationId)

        try await waitUntil("expected rewritten slash-command notification") {
            notificationManager.handleEventCalls.count == 1
        }

        let recordedEvent = try XCTUnwrap(notificationManager.handleEventCalls.first)
        XCTAssertEqual(recordedEvent.conversationId, conversationId)
        XCTAssertEqual(recordedEvent.event, .error(message: "Unknown command: /test-command"))
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

private final class SlashCommandTokenAdapter: AgentAdapter, @unchecked Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    private let input: Int
    private let output: Int
    private let cacheRead: Int
    private let isError: Bool
    private let stopReason: String?
    private let durationMs: Int
    private let costUsd: Double
    private let permissionDenials: [PermissionDenialSummary]

    init(
        input: Int,
        output: Int,
        cacheRead: Int,
        isError: Bool,
        stopReason: String?,
        durationMs: Int,
        costUsd: Double,
        permissionDenials: [PermissionDenialSummary]
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.isError = isError
        self.stopReason = stopReason
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.permissionDenials = permissionDenials
    }

    func buildArgs(config: AgentConfig) -> [String] {
        []
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        guard json["type"] as? String == "tokens" else {
            return []
        }

        return [
            .tokens(
                input: input,
                output: output,
                cacheRead: cacheRead,
                isError: isError,
                stopReason: stopReason,
                durationMs: durationMs,
                costUsd: costUsd,
                permissionDenials: permissionDenials
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

        let payload: [String: Any] = ["type": "tokens"]
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

private func withEnvironmentValue(key: String, value: String, perform: () -> Void) {
    let previous = ProcessInfo.processInfo.environment[key]
    setenv(key, value, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    perform()
}
