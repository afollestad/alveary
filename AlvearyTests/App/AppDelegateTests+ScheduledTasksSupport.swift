import Darwin
import Foundation
import SwiftData

@testable import Alveary

@MainActor
final class AppDelegateScheduledTaskLifecycleSpy {
    private(set) var activationCount = 0
    private(set) var reconciliationCount = 0
    private(set) var terminationDates: [Date] = []
    var terminationPreparation: ScheduledTaskTerminationPreparation?

    private let terminationOrderRecorder: AppDelegateShutdownOrderRecorder?

    init(terminationOrderRecorder: AppDelegateShutdownOrderRecorder? = nil) {
        self.terminationOrderRecorder = terminationOrderRecorder
    }

    func recordActivation() {
        activationCount += 1
    }

    func recordReconciliation() {
        reconciliationCount += 1
    }

    func prepareForTermination(at actionDate: Date) -> ScheduledTaskTerminationPreparation? {
        terminationOrderRecorder?.record("scheduled-prepare")
        terminationDates.append(actionDate)
        return terminationPreparation
    }
}

extension AppDelegateTestFixture {
    func makeStartupOrderingAppDelegate(
        recorder: AppDelegateShutdownOrderRecorder,
        sessionManager: AppDelegateStartupOrderSessionManager,
        providerDetection: AppDelegateOrderProviderDetection,
        signalState: AppDelegateProcessSignalState,
        scheduledTaskLifecycle: AppDelegateScheduledTaskLifecycleSpy
    ) -> AppDelegate {
        let recordingAttachmentStore = AppDelegateStartupOrderAttachmentStore(
            underlying: attachmentStore,
            recorder: recorder
        )
        return AppDelegate(
            dependencies: .init(
                agentsManager: agentsManager,
                providerDetection: providerDetection,
                sessionManager: sessionManager,
                attachmentStore: recordingAttachmentStore,
                taskWorkspaceOwnershipService: taskWorkspaceOwnershipService,
                shellRunner: shellRunner,
                modelContainer: modelContainer,
                flushConversationControllers: { [] },
                activateScheduledTasks: {
                    recorder.record("scheduled-activation")
                    scheduledTaskLifecycle.recordActivation()
                },
                reconcileScheduledTasks: {
                    scheduledTaskLifecycle.recordReconciliation()
                },
                teardownVoiceInput: {
                    recorder.record("voice-teardown")
                },
                prepareScheduledTasksForTermination: { actionDate in
                    scheduledTaskLifecycle.prepareForTermination(at: actionDate)
                },
                cleanupRuntimePreferences: {},
                notificationRouter: NotificationRouter(),
                workspaceNotificationCenter: workspaceNotificationCenter,
                notificationCenter: appNotificationCenter,
                disableSuddenTermination: {},
                enableSuddenTermination: {},
                signalProcess: { pid, signal in
                    signalState.signal(pid: pid, signal: signal)
                    if signal == SIGTERM {
                        recorder.record("session-orphan-cleanup")
                    }
                    return 0
                },
                processExists: signalState.contains,
                wakeRefreshDelay: .milliseconds(10),
                shutdownPersistTimeout: 0.05,
                shutdownProcessGrace: 0.05,
                orphanCleanupGrace: 0.05
            )
        )
    }

    func prepareStartupOrderingState(
        sessionManager: AppDelegateStartupOrderSessionManager
    ) async throws -> ModelContext {
        let context = modelContainer.mainContext
        let project = Project(path: "/tmp/scheduled-startup-order", name: "Startup order")
        let thread = AgentThread(name: "Stale draft", isDraft: true, project: project)
        let conversation = Conversation(id: "scheduled-startup-order", provider: "claude", thread: thread)
        context.insert(project)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        await sessionManager.setEntry(
            conversationId: conversation.id,
            entry: SessionEntry(
                cwd: project.path,
                providerId: "claude",
                appSessionId: "scheduled-startup-session",
                launchSessionId: "scheduled-startup-session"
            )
        )
        await shellRunner.enqueue(shellSuccess(
            stdout: AppDelegateClaudeProcessListBuilder()
                .claude(pid: 100, sessionId: "scheduled-startup-session")
                .build()
        ))
        await shellRunner.enqueue(shellSuccess(
            stdout: "p100\nfcwd\nn/tmp/scheduled-startup-order\n"
        ))
        return context
    }
}

actor AppDelegateStartupOrderSessionManager: SessionManager {
    private let recorder: AppDelegateShutdownOrderRecorder
    private var entries: [String: SessionEntry] = [:]

    init(recorder: AppDelegateShutdownOrderRecorder) {
        self.recorder = recorder
    }

    func createEntry(conversationId: String, cwd: String, providerId: String) -> Bool {
        guard entries[conversationId] == nil else {
            return false
        }
        entries[conversationId] = SessionEntry(
            cwd: CanonicalPath.normalize(cwd),
            providerId: providerId,
            appSessionId: conversationId,
            launchSessionId: conversationId
        )
        return true
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
        recorder.record("session-load")
    }

    func persist() throws {}

    func setEntry(conversationId: String, entry: SessionEntry) {
        entries[conversationId] = entry
    }
}

actor AppDelegateOrderProviderDetection: ProviderDetectionService {
    private let recorder: AppDelegateShutdownOrderRecorder

    init(recorder: AppDelegateShutdownOrderRecorder) {
        self.recorder = recorder
    }

    func resolvedPath(for providerId: String) -> String? {
        nil
    }

    func status(for providerId: String) -> ProviderStatus {
        .unchecked
    }

    func checkAllProviders() async {
        recorder.record("provider-refresh")
    }

    func checkProvider(_ providerId: String) async {}
}

private actor AppDelegateStartupOrderAttachmentStore: ConversationAttachmentStore {
    nonisolated let underlying: any ConversationAttachmentStore
    nonisolated let recorder: AppDelegateShutdownOrderRecorder

    init(
        underlying: any ConversationAttachmentStore,
        recorder: AppDelegateShutdownOrderRecorder
    ) {
        self.underlying = underlying
        self.recorder = recorder
    }

    nonisolated func conversationRootDirectory(conversationId: String) -> URL {
        underlying.conversationRootDirectory(conversationId: conversationId)
    }

    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment] {
        try await underlying.copyLocalImages(urls, conversationId: conversationId)
    }

    func storeAppShotScreenshot(
        _ data: Data,
        conversationId: String,
        label: String
    ) async throws -> LocalImageAttachment {
        try await underlying.storeAppShotScreenshot(data, conversationId: conversationId, label: label)
    }

    func cleanupUnreferenced(
        conversationId: String,
        keeping retainedURLs: Set<URL>,
        olderThan age: TimeInterval
    ) async {
        await underlying.cleanupUnreferenced(
            conversationId: conversationId,
            keeping: retainedURLs,
            olderThan: age
        )
    }

    func removeAttachment(at url: URL) async throws {
        try await underlying.removeAttachment(at: url)
    }

    func removeConversationDirectory(conversationId: String) async {
        await underlying.removeConversationDirectory(conversationId: conversationId)
        recorder.record("stale-cleanup")
    }
}
