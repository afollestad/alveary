import AppKit
import Foundation
import SwiftData
import XCTest

@testable import Skep

@MainActor
final class AppDelegateTests: XCTestCase {
    func testStartupWarmupLoadsSessionsTerminatesOnlySessionMappedOrphansAndChecksProviders() async throws {
        let workspaceNotificationCenter = NotificationCenter()
        let appNotificationCenter = NotificationCenter()
        let shellRunner = MockShellRunner()
        let providerDetection = MockProviderDetectionService()
        let sessionManager = MockSessionManager()
        let agentsManager = MockAgentsManager()
        let modelContainer = try makeModelContainer()
        let modelContext = ModelContext(modelContainer)
        let firstConversation = Conversation(id: "conversation-1")
        let secondConversation = Conversation(id: "conversation-2")
        modelContext.insert(firstConversation)
        modelContext.insert(secondConversation)
        try modelContext.save()

        await seedSession(conversationId: "conversation-1", cwd: "/tmp/project-one", on: sessionManager)
        await seedSession(conversationId: "conversation-2", cwd: "/tmp/project-two", on: sessionManager)
        await agentsManager.setTrackedConversationIds(["conversation-2"])

        await shellRunner.enqueue(shellSuccess(
            stdout: ClaudeProcessListBuilder()
                .claude(pid: 100, sessionId: "session-1")
                .claude(pid: 200, sessionId: "session-2")
                .other(pid: 300, command: "/bin/bash -lc echo nope")
                .build()
        ))
        await shellRunner.enqueue(shellSuccess(stdout: "p100\nfcwd\nn/tmp/project-one\n"))
        await shellRunner.enqueue(shellSuccess(stdout: "p200\nfcwd\nn/tmp/project-two\n"))

        let signalState = ProcessSignalState(activePIDs: [100, 200])
        let appDelegate = AppDelegate(
            dependencies: makeDependencies(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: shellRunner,
                modelContainer: modelContainer,
                workspaceNotificationCenter: workspaceNotificationCenter,
                notificationCenter: appNotificationCenter,
                signalProcess: { pid, signal in
                    signalState.signal(pid: pid, signal: signal)
                    return 0
                },
                processExists: { pid in
                    signalState.contains(pid)
                },
                wakeRefreshDelay: .milliseconds(10)
            )
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await waitUntil("expected startup warmup to finish") {
            await providerDetection.checkAllCount() == 1
        }

        let sessionLoadCount = await sessionManager.loadCount()
        let providerCheckCount = await providerDetection.checkAllCount()
        let preservedSession = await sessionManager.hasSession(for: "conversation-1")
        XCTAssertEqual(sessionLoadCount, 1)
        XCTAssertEqual(providerCheckCount, 1)
        XCTAssertTrue(preservedSession)
        XCTAssertEqual(signalState.recordedSignals(), [.init(pid: 100, signal: SIGTERM)])
        XCTAssertTrue(signalState.contains(200))

        let invocations = await shellRunner.invocations
        XCTAssertEqual(invocations.map(\.executable), ["/bin/ps", "/usr/sbin/lsof", "/usr/sbin/lsof"])

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testWakeNotificationCancelsOlderRefreshBeforeRunningProviderCheck() async throws {
        let workspaceNotificationCenter = NotificationCenter()
        let providerDetection = MockProviderDetectionService()
        let sessionManager = MockSessionManager()
        let agentsManager = MockAgentsManager()
        let appDelegate = AppDelegate(
            dependencies: makeDependencies(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: MockShellRunner(),
                modelContainer: try makeModelContainer(),
                workspaceNotificationCenter: workspaceNotificationCenter,
                notificationCenter: NotificationCenter(),
                wakeRefreshDelay: .milliseconds(40)
            )
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await waitUntil("expected initial startup provider detection") {
            await providerDetection.checkAllCount() == 1
        }

        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(10))
        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        try await waitUntil("expected only latest wake refresh to run") {
            await providerDetection.checkAllCount() == 2
        }
        try? await Task.sleep(for: .milliseconds(60))

        let providerCheckCount = await providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 2)
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testStartupWarmupRemovesSessionEntryWhenOrphanedConversationWasDeleted() async throws {
        let shellRunner = MockShellRunner()
        let providerDetection = MockProviderDetectionService()
        let sessionManager = MockSessionManager()
        let agentsManager = MockAgentsManager()

        await seedSession(conversationId: "conversation-1", cwd: "/tmp/project-one", on: sessionManager)
        await shellRunner.enqueue(shellSuccess(
            stdout: ClaudeProcessListBuilder()
                .claude(pid: 100, sessionId: "session-1")
                .build()
        ))
        await shellRunner.enqueue(shellSuccess(stdout: "p100\nfcwd\nn/tmp/project-one\n"))

        let signalState = ProcessSignalState(activePIDs: [100])
        let appDelegate = AppDelegate(
            dependencies: makeDependencies(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: shellRunner,
                modelContainer: try makeModelContainer(),
                workspaceNotificationCenter: NotificationCenter(),
                notificationCenter: NotificationCenter(),
                signalProcess: { pid, signal in
                    signalState.signal(pid: pid, signal: signal)
                    return 0
                },
                processExists: { pid in
                    signalState.contains(pid)
                }
            )
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        try await waitUntil("expected startup warmup to prune stale session entry") {
            !(await sessionManager.hasSession(for: "conversation-1"))
        }

        let providerCheckCount = await providerDetection.checkAllCount()
        XCTAssertEqual(providerCheckCount, 1)
        XCTAssertEqual(signalState.recordedSignals(), [.init(pid: 100, signal: SIGTERM)])

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testManagedProcessesObserverTogglesSuddenTerminationWithSnapshotChanges() async throws {
        let notificationCenter = NotificationCenter()
        let agentsManager = MockAgentsManager()
        let providerDetection = MockProviderDetectionService()
        let sessionManager = MockSessionManager()
        let suddenTerminationState = SuddenTerminationState()
        let appDelegate = AppDelegate(
            dependencies: makeDependencies(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: MockShellRunner(),
                modelContainer: try makeModelContainer(),
                workspaceNotificationCenter: NotificationCenter(),
                notificationCenter: notificationCenter,
                disableSuddenTermination: {
                    suddenTerminationState.recordDisable()
                },
                enableSuddenTermination: {
                    suddenTerminationState.recordEnable()
                }
            )
        )

        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        await agentsManager.setAllProcessesSnapshot([Process()])
        notificationCenter.post(name: .managedProcessesChanged, object: nil)
        XCTAssertEqual(suddenTerminationState.disableCalls, 1)
        XCTAssertEqual(suddenTerminationState.enableCalls, 0)

        await agentsManager.setAllProcessesSnapshot([])
        notificationCenter.post(name: .managedProcessesChanged, object: nil)
        XCTAssertEqual(suddenTerminationState.disableCalls, 1)
        XCTAssertEqual(suddenTerminationState.enableCalls, 1)

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    func testApplicationWillTerminateBeginsShutdownPostsNotificationAndPersistsSessionMap() async throws {
        let notificationCenter = NotificationCenter()
        let agentsManager = MockAgentsManager()
        let providerDetection = MockProviderDetectionService()
        let sessionManager = MockSessionManager()
        let appDelegate = AppDelegate(
            dependencies: makeDependencies(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                shellRunner: MockShellRunner(),
                modelContainer: try makeModelContainer(),
                workspaceNotificationCenter: NotificationCenter(),
                notificationCenter: notificationCenter,
                wakeRefreshDelay: .milliseconds(10),
                shutdownPersistTimeout: 0.2,
            )
        )

        let appWillTerminateNotifications = NotificationCounter()
        let observer = notificationCenter.addObserver(
            forName: .appWillTerminate,
            object: nil,
            queue: nil
        ) { _ in
            appWillTerminateNotifications.increment()
        }
        defer {
            notificationCenter.removeObserver(observer)
        }

        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let shutdownCallCount = await agentsManager.beginShutdownCallCount()
        let persistCount = await sessionManager.persistCount()
        XCTAssertEqual(shutdownCallCount, 1)
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(appWillTerminateNotifications.value, 1)
    }
}

private extension AppDelegateTests {
    func makeDependencies(
        agentsManager: MockAgentsManager,
        providerDetection: MockProviderDetectionService,
        sessionManager: MockSessionManager,
        shellRunner: MockShellRunner,
        modelContainer: ModelContainer,
        workspaceNotificationCenter: NotificationCenter,
        notificationCenter: NotificationCenter,
        disableSuddenTermination: @escaping () -> Void = {},
        enableSuddenTermination: @escaping () -> Void = {},
        signalProcess: @escaping @Sendable (Int32, Int32) -> Int32 = { _, _ in 0 },
        processExists: @escaping @Sendable (Int32) -> Bool = { _ in false },
        wakeRefreshDelay: Duration = .milliseconds(10),
        shutdownPersistTimeout: TimeInterval = 0.05,
        shutdownProcessGrace: TimeInterval = 0.05,
        orphanCleanupGrace: TimeInterval = 0.05
    ) -> AppDelegate.Dependencies {
        .init(
            agentsManager: agentsManager,
            providerDetection: providerDetection,
            sessionManager: sessionManager,
            shellRunner: shellRunner,
            modelContainer: modelContainer,
            workspaceNotificationCenter: workspaceNotificationCenter,
            notificationCenter: notificationCenter,
            disableSuddenTermination: disableSuddenTermination,
            enableSuddenTermination: enableSuddenTermination,
            signalProcess: signalProcess,
            processExists: processExists,
            wakeRefreshDelay: wakeRefreshDelay,
            shutdownPersistTimeout: shutdownPersistTimeout,
            shutdownProcessGrace: shutdownProcessGrace,
            orphanCleanupGrace: orphanCleanupGrace
        )
    }

    func makeModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: configuration
        )
    }

    func seedSession(conversationId: String, cwd: String, on sessionManager: MockSessionManager) async {
        await sessionManager.setEntry(
            conversationId: conversationId,
            entry: SessionEntry(
                cwd: CanonicalPath.normalize(cwd),
                providerId: "claude",
                appSessionId: conversationId.replacingOccurrences(of: "conversation-", with: "session-"),
                launchSessionId: conversationId.replacingOccurrences(of: "conversation-", with: "session-")
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

    func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
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
}

private actor MockProviderDetectionService: ProviderDetectionService {
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

private actor MockSessionManager: SessionManager {
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

private actor MockAgentsManager: AgentsManager {
    private let sharedState = SharedState()
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

private final class SharedState: @unchecked Sendable {
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

private final class ProcessSignalState: @unchecked Sendable {
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

private final class SuddenTerminationState: @unchecked Sendable {
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

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private struct ClaudeProcessListBuilder {
    private var lines: [String] = []

    func claude(pid: Int32, sessionId: String) -> ClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) /opt/homebrew/bin/claude --resume \(sessionId) --verbose")
        return copy
    }

    func other(pid: Int32, command: String) -> ClaudeProcessListBuilder {
        var copy = self
        copy.lines.append(" \(pid) \(command)")
        return copy
    }

    func build() -> String {
        lines.joined(separator: "\n") + "\n"
    }
}

private struct WaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}
