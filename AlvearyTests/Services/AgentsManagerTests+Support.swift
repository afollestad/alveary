import Foundation
import XCTest

@testable import Alveary

@MainActor
func makeSettings(extraArgs: String? = nil) -> InMemorySettingsService {
    let providerConfig = ProviderCustomConfig(extraArgs: extraArgs)
    return InMemorySettingsService(current: AppSettings(providerConfigs: ["claude": providerConfig]))
}

@MainActor
func makeTestManager(
    settings: InMemorySettingsService,
    providerDetection: any ProviderDetectionService,
    sessionManager: InMemorySessionManager = InMemorySessionManager(),
    notificationManager: NotificationManager = StubNotificationManager(),
    claudeHookServer: any ClaudeHookServer = DisabledClaudeHookServer(),
    adapterFactory: @escaping @Sendable (String) -> AgentAdapter
) -> DefaultAgentsManager {
    DefaultAgentsManager(
        sessionManager: sessionManager,
        providerDetection: providerDetection,
        environmentBuilder: DefaultAgentEnvironmentBuilder(),
        providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
        settingsService: settings,
        notificationManager: notificationManager,
        claudeHookServer: claudeHookServer,
        adapterFactory: adapterFactory
    )
}

@MainActor
func waitUntil(
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

func firstEvent(
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

struct WaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}

struct TempExecutable {
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

actor StubProviderDetectionService: ProviderDetectionService {
    private let path: String?

    init(resolvedPath: String? = nil) {
        self.path = resolvedPath
    }

    func resolvedPath(for providerId: String) -> String? {
        path
    }

    func status(for providerId: String) -> ProviderStatus {
        .unchecked
    }

    func checkAllProviders() async {}

    func checkProvider(_ providerId: String) async {}
}

final class EchoAgentAdapter: AgentAdapter, @unchecked Sendable {
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

final class PermissionModeEchoAgentAdapter: AgentAdapter, @unchecked Sendable {
    let supportsBidirectionalStreaming = true
    let supportsMidTurnSteering = false

    func buildArgs(config: AgentConfig) -> [String] {
        []
    }

    func envOverrides(config: AgentConfig) -> [String: String] {
        [:]
    }

    func decode(_ json: [String: Any]) -> [ConversationEvent] {
        guard json["type"] as? String == "permission_mode",
              let permissionMode = json["value"] as? String else {
            return []
        }
        return [.permissionModeChanged(permissionMode)]
    }

    func finalize() -> [ConversationEvent] {
        []
    }

    func sendMessage(_ message: String, to process: Process) throws {
        guard let stdin = process.standardInput as? Pipe else {
            throw AgentError.stdinClosed
        }

        let payload: [String: String] = [
            "type": "permission_mode",
            "value": message
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

final class RecordingLaunchAdapter: AgentAdapter, @unchecked Sendable {
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
final class StubNotificationManager: NotificationManager {
    func handleEvent(_ event: ConversationEvent, conversationId: String) {}
    func markConversationRead(conversationId: String) {}
    func handleAppVisibilityChanged() {}
    func refreshBadgeCount() {}
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {}
}

func agentsManagerLaunchContainsSubsequence(_ values: [String], _ subsequence: [String]) -> Bool {
    guard !subsequence.isEmpty, subsequence.count <= values.count else {
        return subsequence.isEmpty
    }

    for startIndex in 0...(values.count - subsequence.count)
    where Array(values[startIndex..<(startIndex + subsequence.count)]) == subsequence {
        return true
    }

    return false
}
