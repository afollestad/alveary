import AgentCLIKit
import Foundation

actor DefaultAgentsManager: AgentsManager, ConversationRuntimeStore {
    let agentCLIKitServices: AgentCLIKitHostServices
    let sessionManager: SessionManager
    let providerDetection: ProviderDetectionService
    let environmentBuilder: AgentEnvironmentBuilder
    let providerRegistry: ProviderRegistry
    let settingsService: SettingsService
    let keepAwakeService: KeepAwakeService
    let notificationManager: NotificationManager
    let threadActivityRecorder: any ThreadActivityRecording
    let claudeApprovalPersistenceStore: any ClaudeApprovalPersistenceStore
    let providerSessionBindingStore: any ProviderSessionBindingStore

    var eventBuffers: [String: ManagedEventBuffer] = [:]
    var closingConversationIds: Set<String> = []
    var pendingSessionRemovalIds: Set<String> = []
    var pendingSessionRemovalErrors: [String: String] = [:]
    var spawningIds: Set<String> = []
    var reconfiguringIds: Set<String> = []
    var pendingKillIds: Set<String> = []
    var deniedToolUseIdsByConversation: [String: Set<String>] = [:]
    var cancelledInteractionsByConversation: [String: CancelledInteractionResolution] = [:]
    var agentCLIKitEventTasks: [String: Task<Void, Never>] = [:]
    var agentCLIKitStatusTasks: [String: Task<Void, Never>] = [:]
    var agentCLIKitGenerationByConversation: [String: Int] = [:]
    var agentCLIKitGenerationUUIDs: [String: [Int: UUID]] = [:]
    var agentCLIKitStatuses: [String: AgentCLIKit.AgentRuntimeStatus] = [:]
    var recordedProviderSessionBindings: Set<ProviderSessionBinding> = []
    var hasInstalledAgentCLIKitLiveHookHandler = false

    let shutdownRequested = LockedState(false)
    let processSnapshot = LockedState([Process]())
    let statusSnapshot = LockedState([String: ActivitySignal]())
    let conversationStatesStore = LockedState([String: ConversationState]())

    init(
        agentCLIKitServices: AgentCLIKitHostServices,
        sessionManager: SessionManager,
        providerDetection: ProviderDetectionService,
        environmentBuilder: AgentEnvironmentBuilder,
        providerRegistry: ProviderRegistry,
        settingsService: SettingsService,
        keepAwakeService: KeepAwakeService,
        notificationManager: NotificationManager,
        threadActivityRecorder: any ThreadActivityRecording = NoopThreadActivityRecorder(),
        claudeApprovalPersistenceStore: any ClaudeApprovalPersistenceStore = DisabledClaudeApprovalPersistenceStore(),
        providerSessionBindingStore: any ProviderSessionBindingStore = NoopProviderSessionBindingStore()
    ) {
        self.agentCLIKitServices = agentCLIKitServices
        self.sessionManager = sessionManager
        self.providerDetection = providerDetection
        self.environmentBuilder = environmentBuilder
        self.providerRegistry = providerRegistry
        self.settingsService = settingsService
        self.keepAwakeService = keepAwakeService
        self.notificationManager = notificationManager
        self.threadActivityRecorder = threadActivityRecorder
        self.claudeApprovalPersistenceStore = claudeApprovalPersistenceStore
        self.providerSessionBindingStore = providerSessionBindingStore
    }

    @MainActor
    func conversationState(for conversationId: String) -> ConversationState {
        conversationStatesStore.withLock { store in
            if let existing = store[conversationId] {
                return existing
            }

            let state = ConversationState()
            store[conversationId] = state
            return state
        }
    }

    nonisolated func beginShutdown() {
        shutdownRequested.withLock { $0 = true }
        let agentCLIKitServices = agentCLIKitServices
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await agentCLIKitServices.runtime.shutdown()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    nonisolated func status(for conversationId: String) -> ActivitySignal {
        statusSnapshot.withLock { $0[conversationId] ?? .neutral }
    }

    nonisolated var allStatuses: [String: ActivitySignal] {
        statusSnapshot.withLock { $0 }
    }

    nonisolated var allProcessesSnapshot: [Process] {
        processSnapshot.withLock { $0 }
    }

    func hasTrackedProcess(conversationId: String) -> Bool {
        agentCLIKitStatuses[conversationId]?.processIdentifier != nil
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
    }

    func isRunning(conversationId: String) -> Bool {
        agentCLIKitStatuses[conversationId]?.isProcessRunning == true ||
            spawningIds.contains(conversationId) ||
            reconfiguringIds.contains(conversationId)
    }

    nonisolated func updateStatus(_ signal: ActivitySignal, for conversationId: String) {
        let didChange = statusSnapshot.withLock { statuses in
            let didChange = statuses[conversationId] != signal
            statuses[conversationId] = signal
            return didChange
        }
        syncKeepAwakeRuntimeActivity()
        guard didChange else {
            return
        }
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationId, "signal": signal]
            )
        }
    }

    nonisolated func clearStatus(for conversationId: String) {
        _ = statusSnapshot.withLock { $0.removeValue(forKey: conversationId) }
        syncKeepAwakeRuntimeActivity()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationId, "signal": ActivitySignal.neutral]
            )
        }
    }

}

struct CancelledInteractionResolution: Equatable {
    // AgentCLIKit can keep reporting a denied prompt/plan-exit interaction as running
    // or waiting until the provider emits terminal fallout. Scope suppression to this
    // interaction/generation so new user work can clear it normally.
    let toolUseId: String
    let agentGeneration: Int?
}

private extension DefaultAgentsManager {
    nonisolated func syncKeepAwakeRuntimeActivity() {
        Task { [weak self, keepAwakeService] in
            let active = self?.hasKeepAwakeRuntimeActivity() ?? false
            await keepAwakeService.setActive(active, for: .runtimeActivity)
        }
    }

    nonisolated func hasKeepAwakeRuntimeActivity() -> Bool {
        statusSnapshot.withLock { statuses in
            statuses.values.contains { signal in
                signal == .busy || signal == .waitingForUser
            }
        }
    }
}
