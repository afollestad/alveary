import Foundation

let claudeHookTokenEnvironmentKey = "ALVEARY_HOOK_TOKEN"

actor DefaultAgentsManager: AgentsManager, ConversationRuntimeStore {
    let sessionManager: SessionManager
    let providerDetection: ProviderDetectionService
    let environmentBuilder: AgentEnvironmentBuilder
    let providerRegistry: ProviderRegistry
    let settingsService: SettingsService
    let notificationManager: NotificationManager
    let claudeHookServer: any ClaudeHookServer
    let adapterFactory: @Sendable (String) -> AgentAdapter

    var processes: [String: Process] = [:]
    var adapters: [String: AgentAdapter] = [:]
    var hookTokens: [String: String] = [:]
    var streamTasks: [String: Task<Void, Never>] = [:]
    var eventBuffers: [String: ManagedEventBuffer] = [:]
    var stdinWriteTails: [String: PendingStdinWrite] = [:]
    var suppressedExitPIDs: [String: Set<Int32>] = [:]
    var closingConversationIds: Set<String> = []
    var pendingSessionRemovalIds: Set<String> = []
    var pendingSessionRemovalErrors: [String: String] = [:]
    var spawningIds: Set<String> = []
    var reconfiguringIds: Set<String> = []
    var pendingKillIds: Set<String> = []
    var deniedToolUseIdsByConversation: [String: Set<String>] = [:]

    let shutdownRequested = LockedState(false)
    let processSnapshot = LockedState([Process]())
    let statusSnapshot = LockedState([String: ActivitySignal]())
    let conversationStatesStore = LockedState([String: ConversationState]())

    init(
        sessionManager: SessionManager,
        providerDetection: ProviderDetectionService,
        environmentBuilder: AgentEnvironmentBuilder,
        providerRegistry: ProviderRegistry,
        settingsService: SettingsService,
        notificationManager: NotificationManager,
        claudeHookServer: any ClaudeHookServer = DisabledClaudeHookServer(),
        adapterFactory: @escaping @Sendable (String) -> AgentAdapter = { providerID in
            switch providerID {
            case "claude":
                return ClaudeAdapter()
            default:
                fatalError("Unknown provider: \(providerID). Add an adapter case for this provider.")
            }
        }
    ) {
        self.sessionManager = sessionManager
        self.providerDetection = providerDetection
        self.environmentBuilder = environmentBuilder
        self.providerRegistry = providerRegistry
        self.settingsService = settingsService
        self.notificationManager = notificationManager
        self.claudeHookServer = claudeHookServer
        self.adapterFactory = adapterFactory
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
        processes[conversationId] != nil
    }

    func hasInflightLifecycle(conversationId: String) -> Bool {
        spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
    }

    func isRunning(conversationId: String) -> Bool {
        if let process = processes[conversationId] {
            return process.isRunning || spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
        }

        return spawningIds.contains(conversationId) || reconfiguringIds.contains(conversationId)
    }

    func resolveAdapter(for providerId: String) -> AgentAdapter {
        adapterFactory(providerId)
    }

    nonisolated func updateStatus(_ signal: ActivitySignal, for conversationId: String) {
        statusSnapshot.withLock { $0[conversationId] = signal }
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
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationId, "signal": ActivitySignal.neutral]
            )
        }
    }

}
