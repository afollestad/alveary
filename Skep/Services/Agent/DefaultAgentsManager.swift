import Foundation

actor DefaultAgentsManager: AgentsManager, ConversationRuntimeStore {
    let sessionManager: SessionManager
    let providerDetection: ProviderDetectionService
    let environmentBuilder: AgentEnvironmentBuilder
    let providerRegistry: ProviderRegistry
    let settingsService: SettingsService
    let notificationManager: NotificationManager
    let adapterFactory: @Sendable (String) -> AgentAdapter

    var processes: [String: Process] = [:]
    var adapters: [String: AgentAdapter] = [:]
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

    nonisolated func readAgentOutput(stdout: FileHandle, stderr: FileHandle, adapter: AgentAdapter) -> AsyncStream<ConversationEvent> {
        return AsyncStream { continuation in
            let stderrBuffer = StderrBuffer(maxLines: 20)

            let stderrTask = Task.detached {
                do {
                    for try await line in stderr.bytes.lines {
                        stderrBuffer.append(line)
                    }
                } catch {
                    // stderr closes on normal exit.
                }
            }

            Task.detached {
                do {
                    for try await line in stdout.bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else {
                                continue
                            }

                            let prefix = String(trimmed.prefix(240))
                            let stderrTail = stderrBuffer.lastLines.joined(separator: "\n")
                            let message = if stderrTail.isEmpty {
                                "Malformed agent stdout line: \(prefix)"
                            } else {
                                "Malformed agent stdout line: \(prefix)\n\nStderr:\n\(stderrTail)"
                            }
                            continuation.yield(.error(message: message))
                            break
                        }

                        for event in adapter.decode(json) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    let stderrTail = stderrBuffer.lastLines.joined(separator: "\n")
                    let message = if stderrTail.isEmpty {
                        "Stream read failed: \(error.localizedDescription)"
                    } else {
                        "Agent error: \(stderrTail)"
                    }
                    continuation.yield(.error(message: message))
                }

                _ = await stderrTask.result
                for event in adapter.finalize() {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []
    private var writeIndex = 0
    private var isFull = false
    private let capacity: Int

    init(maxLines: Int) {
        self.capacity = maxLines
        buffer.reserveCapacity(maxLines)
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(line)
            if buffer.count == capacity {
                isFull = true
            }
        } else {
            buffer[writeIndex] = line
        }
        writeIndex = (writeIndex + 1) % capacity
    }

    var lastLines: [String] {
        lock.lock()
        defer { lock.unlock() }

        if !isFull {
            return buffer
        }

        return Array(buffer[writeIndex...]) + Array(buffer[..<writeIndex])
    }
}
