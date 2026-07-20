import enum AgentCLIKit.JSONValue
import AppKit
import Foundation
import SwiftData

@testable import Alveary

@MainActor
struct AppDelegateTestFixture {
    let workspaceNotificationCenter = NotificationCenter()
    let appNotificationCenter = NotificationCenter()
    let shellRunner = MockShellRunner()
    let providerDetection = AppDelegateMockProviderDetectionService()
    let sessionManager = AppDelegateMockSessionManager()
    let agentsManager = AppDelegateMockAgentsManager()
    let modelContainer: ModelContainer
    let attachmentRoot: URL
    let attachmentStore: DefaultConversationAttachmentStore
    let taskWorkspaceOwnershipService: DefaultTaskWorkspaceOwnershipService

    init() throws {
        modelContainer = try Self.makeModelContainer()
        attachmentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-app-delegate-tests-\(UUID().uuidString)", isDirectory: true)
        attachmentStore = DefaultConversationAttachmentStore(rootDirectory: attachmentRoot)
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-app-delegate-workspaces-\(UUID().uuidString)", isDirectory: true)
        taskWorkspaceOwnershipService = DefaultTaskWorkspaceOwnershipService(
            privateWorkspacesRoot: workspaceRoot.appendingPathComponent("Private", isDirectory: true),
            worktreeOwnershipRecordsRoot: workspaceRoot.appendingPathComponent("Worktrees", isDirectory: true)
        )
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
        flushConversationControllers: @escaping @MainActor () -> [ConversationControllerFlushFailure] = { [] },
        teardownVoiceInput: @escaping @MainActor () -> Void = {},
        scheduledTaskLifecycle: AppDelegateScheduledTaskLifecycleSpy? = nil,
        cleanupRuntimePreferences: @escaping @MainActor () -> Void = {},
        disableSuddenTermination: @escaping () -> Void = {},
        enableSuddenTermination: @escaping () -> Void = {}
    ) -> AppDelegate {
        AppDelegate(
            dependencies: .init(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                attachmentStore: attachmentStore,
                taskWorkspaceOwnershipService: taskWorkspaceOwnershipService,
                shellRunner: shellRunner,
                modelContainer: modelContainer,
                flushConversationControllers: flushConversationControllers,
                activateScheduledTasks: {
                    scheduledTaskLifecycle?.recordActivation()
                },
                reconcileScheduledTasks: {
                    scheduledTaskLifecycle?.recordReconciliation()
                },
                teardownVoiceInput: teardownVoiceInput,
                prepareScheduledTasksForTermination: { actionDate in
                    scheduledTaskLifecycle?.prepareForTermination(at: actionDate)
                },
                cleanupRuntimePreferences: cleanupRuntimePreferences,
                notificationRouter: NotificationRouter(),
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
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
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

    func sendMessage(
        _ message: String,
        conversationId: String,
        activityVisibility: AgentTurnActivityVisibility,
        attachments: [LocalImageAttachment],
        metadata: [String: JSONValue]
    ) async throws {}

    func resolveToolApproval(_ request: AgentToolApprovalResolutionRequest) async throws -> Bool {
        false
    }

    func toolApprovalSelection(
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async -> ToolApprovalSelection? {
        nil
    }

    func recordToolApprovalSelection(
        _ selection: ToolApprovalSelection,
        providerId: String,
        conversationId: String,
        sessionId: String
    ) async {}

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

    func reconfigureSession(conversationId: String, config: AgentSpawnConfig) async throws -> AgentSessionReconfigureResult {
        .restarted
    }

    func startFreshSession(conversationId: String, config: AgentSpawnConfig) async throws {}

    func markPersisted(conversationId: String, generation: UUID, upTo index: Int) {}

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        .neutral
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        [:]
    }

    nonisolated func beginShutdown() {
        sharedState.shutdownOrderRecorder?.record("shutdown")
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

    nonisolated func setShutdownOrderRecorder(_ recorder: AppDelegateShutdownOrderRecorder) {
        sharedState.shutdownOrderRecorder = recorder
    }
}

final class AppDelegateSharedState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProcesses: [Process] = []
    private var shutdownCalls = 0
    private var storedShutdownOrderRecorder: AppDelegateShutdownOrderRecorder?

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

    var shutdownOrderRecorder: AppDelegateShutdownOrderRecorder? {
        get {
            lock.withLock { storedShutdownOrderRecorder }
        }
        set {
            lock.withLock { storedShutdownOrderRecorder = newValue }
        }
    }
}

final class AppDelegateShutdownOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func record(_ value: String) {
        lock.withLock { storedValues.append(value) }
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
