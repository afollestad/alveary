import Foundation
import XCTest

@testable import Alveary

@MainActor
func makeSettings(cliPath: String, extraArgs: String? = nil) -> InMemorySettingsService {
    let providerConfig = ProviderCustomConfig(cli: cliPath, extraArgs: extraArgs)
    return InMemorySettingsService(current: AppSettings(providerConfigs: ["claude": providerConfig]))
}

@MainActor
func makeTestManager(
    settings: InMemorySettingsService,
    sessionManager: InMemorySessionManager = InMemorySessionManager(),
    claudeHookServer: any ClaudeHookServer = DisabledClaudeHookServer(),
    adapterFactory: @escaping @Sendable (String) -> AgentAdapter
) -> DefaultAgentsManager {
    DefaultAgentsManager(
        sessionManager: sessionManager,
        providerDetection: StubProviderDetectionService(),
        environmentBuilder: DefaultAgentEnvironmentBuilder(),
        providerRegistry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
        settingsService: settings,
        notificationManager: StubNotificationManager(),
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

actor StubClaudeHookServer: ClaudeHookServer {
    enum Event: Equatable {
        case updatePermissionMode(permissionMode: String?, conversationId: String)
        case recordDecision(ClaudeToolApprovalResolution, ClaudeToolApprovalKey)
        case recordSessionApproval(AgentSessionApprovalGrant)
        case discardSessionApproval(AgentSessionApprovalGrant)
        case removeSessionApprovals(conversationId: String, sessionId: String)
        case discardDecision(ClaudeToolApprovalKey)
        case invalidateToken(String)
    }

    private var launchConfigs: [ClaudeHookLaunchConfig?]
    private var recordedDecisions: [(ClaudeToolApprovalDecision, ClaudeToolApprovalKey)] = []
    private var recordedSessionApprovals: [AgentSessionApprovalGrant] = []
    private var discardedSessionApprovalStorage: [AgentSessionApprovalGrant] = []
    private var removedSessionApprovalIDStorage: [(conversationId: String, sessionId: String)] = []
    private var discardedDecisions: [ClaudeToolApprovalKey] = []
    private var invalidatedTokens: [String] = []
    private var recordedEvents: [Event] = []

    init(launchConfig: ClaudeHookLaunchConfig?) {
        self.launchConfigs = [launchConfig]
    }

    init(launchConfigs: [ClaudeHookLaunchConfig?]) {
        self.launchConfigs = launchConfigs
    }

    func prepareLaunch(
        permissionMode: String?,
        conversationId: String
    ) async -> ClaudeHookLaunchConfig? {
        guard launchConfigs.count > 1 else {
            return launchConfigs.first ?? nil
        }
        return launchConfigs.removeFirst()
    }

    func updatePermissionMode(_ permissionMode: String?, for conversationId: String) async {
        recordedEvents.append(.updatePermissionMode(permissionMode: permissionMode, conversationId: conversationId))
    }

    func recordDecision(_ resolution: ClaudeToolApprovalResolution, for key: ClaudeToolApprovalKey) async {
        recordedDecisions.append((resolution.decision, key))
        recordedEvents.append(.recordDecision(resolution, key))
    }

    func recordSessionApproval(_ approval: AgentSessionApprovalGrant) async -> SessionApprovalRecordResult {
        recordedSessionApprovals.append(approval)
        recordedEvents.append(.recordSessionApproval(approval))
        return SessionApprovalRecordResult(isEffective: true, wasInserted: true)
    }

    func sessionApprovals() -> [AgentSessionApprovalGrant] {
        recordedSessionApprovals
    }

    func discardSessionApproval(_ approval: AgentSessionApprovalGrant) async {
        discardedSessionApprovalStorage.append(approval)
        recordedEvents.append(.discardSessionApproval(approval))
    }

    func discardedSessionApprovals() -> [AgentSessionApprovalGrant] {
        discardedSessionApprovalStorage
    }

    func removeSessionApprovals(conversationId: String, sessionId: String) async {
        removedSessionApprovalIDStorage.append((conversationId: conversationId, sessionId: sessionId))
        recordedEvents.append(.removeSessionApprovals(conversationId: conversationId, sessionId: sessionId))
    }

    func removedSessionApprovalIDs() -> [(conversationId: String, sessionId: String)] {
        removedSessionApprovalIDStorage
    }

    func decisions() -> [(ClaudeToolApprovalDecision, ClaudeToolApprovalKey)] {
        recordedDecisions
    }

    func discardDecision(for key: ClaudeToolApprovalKey) {
        discardedDecisions.append(key)
        recordedEvents.append(.discardDecision(key))
    }

    func discards() -> [ClaudeToolApprovalKey] {
        discardedDecisions
    }

    func invalidateToken(_ token: String) {
        invalidatedTokens.append(token)
        recordedEvents.append(.invalidateToken(token))
    }

    func invalidations() -> [String] {
        invalidatedTokens
    }

    func events() -> [Event] {
        recordedEvents
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
    func resolvedPath(for providerId: String) -> String? {
        nil
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
