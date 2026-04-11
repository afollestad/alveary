import AppKit
import Foundation
import SwiftData

@testable import Skep

@MainActor
struct AppDelegateTestFixture {
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    let shellRunner = MockShellRunner()
    let providerDetection = AppDelegateMockProviderDetectionService()
    let sessionManager = AppDelegateMockSessionManager()
    let agentsManager = AppDelegateMockAgentsManager()
    let modelContainer: ModelContainer

    init() throws {
        modelContainer = try Self.makeModelContainer()
    }

    func insertConversations(_ ids: [String]) throws {
        let modelContext = ModelContext(modelContainer)
        for id in ids {
            modelContext.insert(Conversation(id: id))
        }
        try modelContext.save()
    }

    func seedSessions(_ sessions: [(conversationId: String, cwd: String)]) async {
        for session in sessions {
            await sessionManager.setEntry(
                conversationId: session.conversationId,
                entry: SessionEntry(
                    cwd: CanonicalPath.normalize(session.cwd),
                    providerId: "claude",
                    appSessionId: session.conversationId.replacingOccurrences(of: "conversation-", with: "session-"),
                    launchSessionId: session.conversationId.replacingOccurrences(of: "conversation-", with: "session-")
                )
            )
        }
    }

    func makeAppDelegate(
        signalState: AppDelegateProcessSignalState? = nil,
        wakeRefreshDelay: Duration = .milliseconds(10),
        shutdownPersistTimeout: TimeInterval = 0.05,
        disableSuddenTermination: @escaping () -> Void = {},
        enableSuddenTermination: @escaping () -> Void = {}
    ) -> AppDelegate {
        AppDelegate(
            dependencies: .init(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: shellRunner,
                modelContainer: modelContainer,
                workspaceNotificationCenter: workspaceNotificationCenter,
                notificationCenter: appNotificationCenter,
                disableSuddenTermination: disableSuddenTermination,
                enableSuddenTermination: enableSuddenTermination,
                signalProcess: { pid, signal in
                    signalState?.signal(pid: pid, signal: signal)
                    return 0
                },
                processExists: { pid in
                    signalState?.contains(pid) ?? false
                },
                wakeRefreshDelay: wakeRefreshDelay,
                shutdownPersistTimeout: shutdownPersistTimeout,
                shutdownProcessGrace: 0.05,
                orphanCleanupGrace: 0.05
            )
        )
    }

    func shellSuccess(stdout: String) -> MockShellRunner.Response {
        .success(
            ShellResult(
                stdout: stdout,
                stderr: "",
                exitCode: 0,
                stdoutWasTruncated: false,
                stderrWasTruncated: false
            )
        )
    }

    func waitForProviderChecks(_ count: Int, description: String) async throws {
        try await appDelegateWaitUntil(description) {
            await providerDetection.checkAllCount() == count
        }
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
    }
}

@MainActor
func appDelegateWaitUntil(
    _ description: String,
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @MainActor () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if try await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }

    throw AppDelegateWaitTimeoutError(description: description)
}

actor AppDelegateMockProviderDetectionService: ProviderDetectionService {
    private var checkAllInvocations = 0

    func resolvedPath(for providerId: String) -> String? {
        nil
    }

    func status(for providerId: String) -> ProviderStatus {
        .unchecked
    }

    func checkAllProviders() async {
        checkAllInvocations += 1
    }

    func checkProvider(_ providerId: String) async {}

    func checkAllCount() -> Int {
        checkAllInvocations
    }
}

actor AppDelegateMockSessionManager: SessionManager {
    private var entries: [String: SessionEntry] = [:]
    private var loadInvocations = 0
    private var persistInvocations = 0

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        false
    }

    func removeEntry(for conversationId: String) throws {
        entries.removeValue(forKey: conversationId)
    }

    func hasSession(for conversationId: String) -> Bool {
        entries[conversationId] != nil
    }

    func sessionId(for conversationId: String) -> String {
        entries[conversationId]?.appSessionId ?? ""
    }

    func conversationId(forSessionId sessionId: String, cwd: String, providerId: String) -> String? {
        let normalizedCWD = CanonicalPath.normalize(cwd)
        return entries.first { _, entry in
            entry.providerId == providerId &&
                entry.cwd == normalizedCWD &&
                (entry.appSessionId == sessionId || entry.launchSessionId == sessionId)
        }?.key
    }

    func updateSessionId(for conversationId: String, newSessionId: String) throws {
        guard var entry = entries[conversationId] else {
            return
        }
        entry.appSessionId = newSessionId
        entries[conversationId] = entry
    }

    func load() {
        loadInvocations += 1
    }

    func persist() throws {
        persistInvocations += 1
    }

    func setEntry(conversationId: String, entry: SessionEntry) {
        entries[conversationId] = entry
    }

    func loadCount() -> Int {
        loadInvocations
    }

    func persistCount() -> Int {
        persistInvocations
    }
}

actor AppDelegateMockAgentsManager: AgentsManager {
    private let sharedState = AppDelegateSharedState()
    private var trackedConversationIds: Set<String> = []
    private var inflightConversationIds: Set<String> = []

    func spawn(id: String, config: AgentSpawnConfig, forkSession: Bool) async throws {}

    func subscribe(conversationId: String, afterIndex: Int) -> AgentEventSubscription? {
        nil
    }

    func sendMessage(_ message: String, conversationId: String) async throws {}

    func cancelTurn(conversationId: String) {}

    func destroyRuntime(conversationId: String) async throws {}

    func kill(conversationId: String) {}

    func killAll() {}

    func isRunning(conversationId: String) -> Bool {
        false
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        trackedConversationIds.contains(conversationId)
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        inflightConversationIds.contains(conversationId)
    }

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        .neutral
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        [:]
    }

    nonisolated func beginShutdown() {
        sharedState.beginShutdownCalls += 1
    }

    nonisolated var allProcessesSnapshot: [Process] {
        sharedState.allProcessesSnapshot
    }

    func setTrackedConversationIds(_ ids: Set<String>) {
        trackedConversationIds = ids
    }

    func setInflightConversationIds(_ ids: Set<String>) {
        inflightConversationIds = ids
    }

    func setAllProcessesSnapshot(_ processes: [Process]) {
        sharedState.allProcessesSnapshot = processes
    }

    func beginShutdownCallCount() -> Int {
        sharedState.beginShutdownCalls
    }
}

final class AppDelegateSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProcesses: [Process] = []
    private var shutdownCalls = 0

    var allProcessesSnapshot: [Process] {
        get {
            lock.withLock { storedProcesses }
        }
        set {
            lock.withLock { storedProcesses = newValue }
        }
    }

    var beginShutdownCalls: Int {
        get {
            lock.withLock { shutdownCalls }
        }
        set {
            lock.withLock { shutdownCalls = newValue }
        }
    }
}

final class AppDelegateProcessSignalState: @unchecked Sendable {
    struct SignalCall: Equatable {
        let pid: Int32
        let signal: Int32
    }

    private let lock = NSLock()
    private var activePIDs: Set<Int32>
    private var signals: [SignalCall] = []

    init(activePIDs: Set<Int32>) {
        self.activePIDs = activePIDs
    }

    func signal(pid: Int32, signal: Int32) {
        lock.withLock {
            signals.append(SignalCall(pid: pid, signal: signal))
            if signal == SIGTERM || signal == SIGKILL {
                activePIDs.remove(pid)
            }
        }
    }

    func contains(_ pid: Int32) -> Bool {
        lock.withLock { activePIDs.contains(pid) }
    }

    func recordedSignals() -> [SignalCall] {
        lock.withLock { signals }
    }
}

final class AppDelegateSuddenTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDisableCalls = 0
    private var storedEnableCalls = 0

    var disableCalls: Int {
        lock.withLock { storedDisableCalls }
    }

    var enableCalls: Int {
        lock.withLock { storedEnableCalls }
    }

    func recordDisable() {
        lock.withLock { storedDisableCalls += 1 }
    }

    func recordEnable() {
        lock.withLock { storedEnableCalls += 1 }
    }
}

final class AppDelegateNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

struct AppDelegateClaudeProcessListBuilder {
    private var lines: [String] = []

    func claude(pid: Int32, sessionId: String) -> AppDelegateClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) /opt/homebrew/bin/claude --resume \(sessionId) --verbose")
        return copy
    }

    func other(pid: Int32, command: String) -> AppDelegateClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) \(command)")
        return copy
    }

    func build() -> String {
        lines.joined(separator: "\n") + "\n"
    }
}

struct AppDelegateWaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}
