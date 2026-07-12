@preconcurrency import AppKit
import Darwin
import SwiftData
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies: @unchecked Sendable {
        let agentsManager: any AgentsManager
        let providerDetection: any ProviderDetectionService
        let sessionManager: any SessionManager
        let attachmentStore: any ConversationAttachmentStore
        let shellRunner: any ShellRunner
        let modelContainer: ModelContainer
        let flushConversationControllers: @MainActor () -> [ConversationControllerFlushFailure]
        let notificationRouter: NotificationRouter
        let workspaceNotificationCenter: NotificationCenter
        let notificationCenter: NotificationCenter
        let disableSuddenTermination: () -> Void
        let enableSuddenTermination: () -> Void
        let signalProcess: @Sendable (Int32, Int32) -> Int32
        let processExists: @Sendable (Int32) -> Bool
        let wakeRefreshDelay: Duration
        let shutdownPersistTimeout: TimeInterval
        let shutdownProcessGrace: TimeInterval
        let orphanCleanupGrace: TimeInterval

        @MainActor
        static func live() -> Dependencies {
            let component = AppDI.component
            return Dependencies(
                agentsManager: component.agentsManager,
                providerDetection: component.providerDetectionService,
                sessionManager: component.sessionManager,
                attachmentStore: component.conversationAttachmentStore,
                shellRunner: component.shellRunner,
                modelContainer: component.modelContainer,
                flushConversationControllers: {
                    component.conversationControllerRegistry.flushForTermination()
                },
                notificationRouter: component.notificationRouter,
                workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
                notificationCenter: .default,
                disableSuddenTermination: { ProcessInfo.processInfo.disableSuddenTermination() },
                enableSuddenTermination: { ProcessInfo.processInfo.enableSuddenTermination() },
                signalProcess: { pid, signal in Darwin.kill(pid, signal) },
                processExists: { pid in Self.defaultProcessExists(pid: pid) },
                wakeRefreshDelay: .seconds(2),
                shutdownPersistTimeout: 0.5,
                shutdownProcessGrace: 1.5,
                orphanCleanupGrace: 1.0
            )
        }

        private static func defaultProcessExists(pid: Int32) -> Bool {
            if Darwin.kill(pid, 0) == 0 {
                return true
            }

            return errno == EPERM
        }
    }

    private let dependencies: Dependencies
    private var startupTask: Task<Void, Never>?
    private var wakeRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var managedProcessesObserver: NSObjectProtocol?
    private var suddenTerminationDisabled = false
    private let notificationTapDelegate: NotificationTapDelegate

    override init() {
        let dependencies = Dependencies.live()
        self.dependencies = dependencies
        self.notificationTapDelegate = NotificationTapDelegate(router: dependencies.notificationRouter)
        super.init()
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.notificationTapDelegate = NotificationTapDelegate(router: dependencies.notificationRouter)
        super.init()
    }

    deinit {
        startupTask?.cancel()
        wakeRefreshTask?.cancel()
        if let wakeObserver {
            dependencies.workspaceNotificationCenter.removeObserver(wakeObserver)
        }
        if let managedProcessesObserver {
            dependencies.notificationCenter.removeObserver(managedProcessesObserver)
        }
        if suddenTerminationDisabled {
            dependencies.enableSuddenTermination()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        removeObservers()

        UNUserNotificationCenter.current().delegate = notificationTapDelegate
        let staleDraftConversationIDs = removeStaleDraftThreads()

        startupTask?.cancel()
        startupTask = Task { [weak self] in
            guard let self else {
                return
            }

            for conversationID in staleDraftConversationIDs {
                await dependencies.attachmentStore.removeConversationDirectory(conversationId: conversationID)
            }

            await dependencies.sessionManager.load()
            guard !Task.isCancelled else {
                return
            }

            await cleanupOrphanedClaudeProcessesIfNeeded()
            guard !Task.isCancelled else {
                return
            }

            await dependencies.providerDetection.checkAllProviders()
        }

        wakeObserver = dependencies.workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleWakeRefresh()
            }
        }

        managedProcessesObserver = dependencies.notificationCenter.addObserver(
            forName: .managedProcessesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSuddenTerminationState()
            }
        }

        updateSuddenTerminationState()
    }

    func removeStaleDraftThreads(
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) -> [String] {
        let modelContext = dependencies.modelContainer.mainContext
        let descriptor = FetchDescriptor<AgentThread>(predicate: #Predicate { thread in
            thread.isDraft == true
        })

        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
            let drafts = try modelContext.fetch(descriptor)
            let conversationIDs = drafts.flatMap { draft in
                draft.conversations.map(\.id)
            }
            for draft in drafts {
                modelContext.delete(draft)
            }
            if !drafts.isEmpty {
                try persist(modelContext)
            }
            return conversationIDs
        } catch {
            modelContext.rollback()
            print("[AppDelegate] Failed to remove stale draft threads: \(error)")
            return []
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        wakeRefreshTask?.cancel()

        let controllerFlushFailures = dependencies.flushConversationControllers()
        for failure in controllerFlushFailures {
            print("[AppDelegate] Failed to flush conversation \(failure.key.conversationID): \(failure.message)")
        }
        dependencies.agentsManager.beginShutdown()
        dependencies.notificationCenter.post(name: .appWillTerminate, object: nil)

        let processes = dependencies.agentsManager.allProcessesSnapshot
        for process in processes where process.isRunning {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(dependencies.shutdownProcessGrace)
        while processes.contains(where: { $0.isRunning }) && Date() < deadline {
            usleep(50_000)
        }

        for process in processes where process.isRunning {
            _ = dependencies.signalProcess(process.processIdentifier, SIGKILL)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let sessionManager = dependencies.sessionManager
        // `applicationWillTerminate` blocks the main thread while waiting, so this repair-path
        // persist must stay off `@MainActor` to avoid deadlocking shutdown.
        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            try? await sessionManager.persist()
        }
        _ = semaphore.wait(timeout: .now() + dependencies.shutdownPersistTimeout)

        removeObservers()
        if suddenTerminationDisabled {
            dependencies.enableSuddenTermination()
            suddenTerminationDisabled = false
        }
    }
}

private extension AppDelegate {
    func scheduleWakeRefresh() {
        wakeRefreshTask?.cancel()
        let providerDetection = dependencies.providerDetection
        let delay = dependencies.wakeRefreshDelay
        wakeRefreshTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }

            await providerDetection.checkAllProviders()
        }
    }

    func updateSuddenTerminationState() {
        let hasLiveProcesses = !dependencies.agentsManager.allProcessesSnapshot.isEmpty ||
            dependencies.agentsManager.allStatuses.values.contains { $0 == .busy || $0 == .waitingForUser }
        switch (hasLiveProcesses, suddenTerminationDisabled) {
        case (true, false):
            dependencies.disableSuddenTermination()
            suddenTerminationDisabled = true
        case (false, true):
            dependencies.enableSuddenTermination()
            suddenTerminationDisabled = false
        default:
            break
        }
    }

    func cleanupOrphanedClaudeProcessesIfNeeded() async {
        let candidates = await liveClaudeProcesses()
        guard !candidates.isEmpty else {
            return
        }

        let modelContext = ModelContext(dependencies.modelContainer)
        for candidate in candidates {
            guard !Task.isCancelled else {
                return
            }

            guard let conversationId = await dependencies.sessionManager.conversationId(
                forSessionId: candidate.sessionId,
                cwd: candidate.cwd,
                providerId: "claude"
            ) else {
                continue
            }
            guard !(await dependencies.agentsManager.hasTrackedProcess(conversationId: conversationId)) else {
                continue
            }
            guard !(await dependencies.agentsManager.hasInflightLifecycle(conversationId: conversationId)) else {
                continue
            }

            let conversationStillExists = conversationExists(id: conversationId, in: modelContext)
            await terminateOrphanedProcess(pid: candidate.pid)
            if !conversationStillExists {
                try? await dependencies.sessionManager.removeEntry(for: conversationId)
            }
        }
    }

    func liveClaudeProcesses() async -> [TrackedClaudeProcess] {
        let result: ShellResult
        do {
            result = try await dependencies.shellRunner.run(
                executable: "/bin/ps",
                args: ["-axo", "pid=,command="],
                timeout: .seconds(2),
                stdoutLimitBytes: 1_000_000,
                stderrLimitBytes: 64_000
            )
        } catch {
            return []
        }

        guard result.succeeded else {
            return []
        }

        var processes: [TrackedClaudeProcess] = []
        for candidate in ClaudeProcessCandidate.parse(psOutput: result.stdout) {
            guard let cwd = await workingDirectory(for: candidate.pid) else {
                continue
            }

            processes.append(
                TrackedClaudeProcess(
                    pid: candidate.pid,
                    sessionId: candidate.sessionId,
                    cwd: cwd
                )
            )
        }
        return processes
    }

    func workingDirectory(for pid: Int32) async -> String? {
        let result: ShellResult
        do {
            result = try await dependencies.shellRunner.run(
                executable: "/usr/sbin/lsof",
                args: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
                timeout: .seconds(1),
                stdoutLimitBytes: 32_000,
                stderrLimitBytes: 32_000
            )
        } catch {
            return nil
        }

        guard result.succeeded else {
            return nil
        }

        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard line.first == "n" else {
                continue
            }

            return CanonicalPath.normalize(String(line.dropFirst()))
        }

        return nil
    }

    func conversationExists(id: String, in modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.id == id
            }
        )
        return (try? modelContext.fetch(descriptor).isEmpty) == false
    }

    func terminateOrphanedProcess(pid: Int32) async {
        _ = dependencies.signalProcess(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(dependencies.orphanCleanupGrace)
        while dependencies.processExists(pid) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if dependencies.processExists(pid) {
            _ = dependencies.signalProcess(pid, SIGKILL)
        }
    }

    func removeObservers() {
        if let wakeObserver {
            dependencies.workspaceNotificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        if let managedProcessesObserver {
            dependencies.notificationCenter.removeObserver(managedProcessesObserver)
            self.managedProcessesObserver = nil
        }
    }
}

private struct ClaudeProcessCandidate {
    let pid: Int32
    let sessionId: String

    static func parse(psOutput: String) -> [ClaudeProcessCandidate] {
        psOutput
            .split(whereSeparator: \.isNewline)
            .compactMap(Self.parse(line:))
    }

    private static func parse(line: Substring) -> ClaudeProcessCandidate? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return nil
        }

        let parts = trimmedLine.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let pid = Int32(parts[0]) else {
            return nil
        }

        let command = String(parts[1])
        guard executableBasename(in: command) == "claude",
              let sessionId = sessionId(in: command) else {
            return nil
        }

        return ClaudeProcessCandidate(pid: pid, sessionId: sessionId)
    }

    private static func executableBasename(in command: String) -> String? {
        guard let executable = command.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }

        return executable.split(separator: "/").last.map(String.init)
    }

    private static func sessionId(in command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        for (index, token) in tokens.enumerated() {
            switch token {
            case "--resume", "--session-id":
                let nextIndex = index + 1
                guard nextIndex < tokens.count else {
                    continue
                }
                return tokens[nextIndex]
            default:
                if token.hasPrefix("--resume=") {
                    return String(token.dropFirst("--resume=".count))
                }
                if token.hasPrefix("--session-id=") {
                    return String(token.dropFirst("--session-id=".count))
                }
            }
        }

        return nil
    }
}

private struct TrackedClaudeProcess {
    let pid: Int32
    let sessionId: String
    let cwd: String
}
