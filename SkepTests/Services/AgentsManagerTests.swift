import Foundation
import XCTest

@testable import Skep

@MainActor
final class AgentsManagerTests: XCTestCase {
    func testReconfigureSessionForksExistingSessionAndRebuildsArgsWithUpdatedPermissionModeAndEffort() async throws {
        let executable = try TempExecutable()
        defer { executable.cleanup() }

        let settings = InMemorySettingsService(
            current: AppSettings(
                providerConfigs: [
                    "claude": ProviderCustomConfig(
                        cli: executable.url.path,
                        extraArgs: "--label \"value with spaces\" --mode fast"
                    )
                ]
            )
        )
        let sessionManager = InMemorySessionManager()
        let adapter = RecordingLaunchAdapter()
        let manager = DefaultAgentsManager(
            sessionManager: sessionManager,
            providerDetection: StubProviderDetectionService(),
            environmentBuilder: DefaultAgentEnvironmentBuilder(),
            providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            settingsService: settings,
            notificationManager: StubNotificationManager(),
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

        let launchCalls = adapter.recordedSessionLaunchCalls
        XCTAssertEqual(launchCalls.count, 2)
        XCTAssertEqual(launchCalls.map(\.isResuming), [false, true])
        XCTAssertEqual(launchCalls.map(\.forkSession), [false, true])
        XCTAssertEqual(launchCalls.first?.sessionId, launchCalls.last?.sessionId)

        let expectedExtraArgs = ["--label", "value with spaces", "--mode", "fast"]
        try await waitUntil("expected 2 complete launch log entries after reconfigure") {
            let recordedLaunches = try executable.recordedLaunchArguments()
            return recordedLaunches.count == 2 && recordedLaunches.allSatisfy { launchArgs in
                launchArgs.containsSubsequence(expectedExtraArgs)
            }
        }

        let recordedLaunches = try executable.recordedLaunchArguments()
        XCTAssertEqual(recordedLaunches.count, 2)
        XCTAssertTrue(
            recordedLaunches.allSatisfy { launchArgs in
                launchArgs.containsSubsequence(expectedExtraArgs)
            },
            "Expected every launch to include parsed extra args. Launches: \(recordedLaunches)"
        )

        await manager.kill(conversationId: conversationId)
        try await waitUntil("expected reconfigured process teardown after kill") {
            let hasTrackedProcess = await manager.hasTrackedProcess(conversationId: conversationId)
            let isRunning = await manager.isRunning(conversationId: conversationId)
            return !hasTrackedProcess && !isRunning
        }
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

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(25),
        condition: @escaping () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw WaitTimeoutError(description: description)
    }

    private func firstEvent(
        from stream: AsyncStream<ConversationEvent>,
        description: String,
        timeout: Duration = .seconds(5)
    ) async throws -> ConversationEvent? {
        try await withThrowingTaskGroup(of: ConversationEvent?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitTimeoutError(description: description)
            }

            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}

private struct WaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}

private struct TempExecutable {
    let directory: URL
    let url: URL
    let workingDirectory: URL
    let argumentsLogURL: URL
    let stdinLogURL: URL
    let stdoutLogURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("echo-agent.sh")
        workingDirectory = directory.appendingPathComponent("project", isDirectory: true)
        argumentsLogURL = directory.appendingPathComponent("arguments.log")
        stdinLogURL = directory.appendingPathComponent("stdin.log")
        stdoutLogURL = directory.appendingPathComponent("stdout.log")

        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true, attributes: nil)
        try Data(
            """
            #!/bin/sh
            {
              first=1
              for arg in "$@"; do
                if [ "$first" -eq 0 ]; then
                  printf '\t'
                fi
                printf '%s' "$arg"
                first=0
              done
              printf '\n'
            } >> "\(argumentsLogURL.path)"
            while IFS= read -r line; do
              printf '%s\n' "$line" >> "\(stdinLogURL.path)"
              printf '%s\n' "$line" >> "\(stdoutLogURL.path)"
              /usr/bin/printf '%s\n' "$line"
            done
            """.utf8
        )
        .write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func recordedLaunchArguments() throws -> [[String]] {
        guard FileManager.default.fileExists(atPath: argumentsLogURL.path) else {
            return []
        }

        let contents = try String(contentsOf: argumentsLogURL, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: "\t").map(String.init)
            }
    }

    func recordedInputLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: stdinLogURL.path) else {
            return []
        }

        return try String(contentsOf: stdinLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    func recordedOutputLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: stdoutLogURL.path) else {
            return []
        }

        return try String(contentsOf: stdoutLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor StubProviderDetectionService: ProviderDetectionService {
    func resolvedPath(for providerId: String) -> String? {
        nil
    }

    func status(for providerId: String) -> ProviderStatus {
        .unchecked
    }

    func checkAllProviders() async {}

    func checkProvider(_ providerId: String) async {}
}

private final class EchoAgentAdapter: AgentAdapter, @unchecked Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    private let lock = NSLock()
    private var payloads: [[String: Any]] = []

    var decodedPayloads: [[String: Any]] {
        lock.withLock { payloads }
    }

    func buildArgs(config: AgentConfig) -> [String] {
        []
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        lock.withLock {
            payloads.append(json)
        }

        guard let type = json["type"] as? String else {
            return []
        }

        switch type {
        case "message":
            return [
                .message(
                    role: json["role"] as? String ?? "assistant",
                    content: "echo:\(json["content"] as? String ?? "")",
                    parentToolUseId: nil
                )
            ]
        default:
            return []
        }
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let payload: [String: String] = [
            "type": "message",
            "role": "assistant",
            "content": message
        ]
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

private final class RecordingLaunchAdapter: AgentAdapter, @unchecked Sendable {
    struct SessionLaunchCall: Equatable {
        let sessionId: String
        let cwd: String
        let isResuming: Bool
        let forkSession: Bool
    }

    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    private let lock = NSLock()
    private var buildConfigs: [AgentConfig] = []
    private var sessionLaunchCalls: [SessionLaunchCall] = []

    var recordedBuildConfigs: [AgentConfig] {
        lock.withLock { buildConfigs }
    }

    var recordedSessionLaunchCalls: [SessionLaunchCall] {
        lock.withLock { sessionLaunchCalls }
    }

    func buildArgs(config: AgentConfig) -> [String] {
        lock.withLock {
            buildConfigs.append(config)
        }
        return ClaudeAdapter().buildArgs(config: config)
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        []
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        try stdin.fileHandleForWriting.write(contentsOf: Data((message + "\n").utf8))
    }

    func sessionFilePath(sessionId: String, cwd: String) -> String? {
        nil
    }

    func canResumeSession(sessionId: String, cwd: String) -> Bool {
        false
    }

    func sessionLaunch(sessionId: String, cwd: String, isResuming: Bool, forkSession: Bool) -> SessionLaunchDecision {
        lock.withLock {
            sessionLaunchCalls.append(
                SessionLaunchCall(
                    sessionId: sessionId,
                    cwd: cwd,
                    isResuming: isResuming,
                    forkSession: forkSession
                )
            )
        }

        if isResuming {
            var args = ["--resume", sessionId]
            if forkSession {
                args.append("--fork-session")
            }
            return SessionLaunchDecision(args: args, continuity: .preserved)
        }

        return SessionLaunchDecision(args: ["--session-id", sessionId], continuity: .preserved)
    }
}

@MainActor
private final class StubNotificationManager: NotificationManager {
    func handleEvent(_ event: ConversationEvent, providerName: String, threadName: String?) {}
}

private extension [String] {
    func containsSubsequence(_ subsequence: [String]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else {
            return subsequence.isEmpty
        }

        for startIndex in 0...(count - subsequence.count)
        where Array(self[startIndex..<(startIndex + subsequence.count)]) == subsequence {
            return true
        }

        return false
    }
}
