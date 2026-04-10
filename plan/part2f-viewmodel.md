# Part 2f: ViewModel

ConversationViewModel lifecycle, persistence, and event handling. Setup helpers and outbound routing continue in the [ConversationViewModel Behaviors supplement](supplement-conversation-viewmodel-behaviors.md). Agent status and lifecycle detection are in Part 2g. Continues from Part 2e.

## ConversationViewModel

## Implementation Status

- [x] Phase 3 step #13 is implemented in the repo: `ConversationViewModel`, the placeholder `WorktreeManager` protocol surface used by setup/retry flows, and focused VM regression coverage.

Built in Part 2 because it depends on agent-runtime types (`AgentsManager`, `TurnState`, event streaming) and bridges that runtime to the chat UI. Phase 3 uses the minimal placeholder `WorktreeManager` surface (`create(projectPath:threadName:baseRef:remoteName:)` + `remove()`); Phase 4 expands it to the full worktree API.

```swift
@MainActor @Observable
class ConversationViewModel {  // Skep/ViewModels/ConversationViewModel.swift
    let conversation: Conversation
    /// Launch-scoped runtime state shared across VM recreation.
    private(set) var state: ConversationState
    private let agentsManager: any AgentsManager
    private let runtimeStore: any ConversationRuntimeStore
    private let modelContext: ModelContext
    private let conversationModelID: PersistentIdentifier
    private let settingsService: SettingsService
    private let worktreeManager: WorktreeManager
    private let providerSetup: ProviderSetupService
    private var subscriptionTask: Task<Void, Never>?
    private static let maxRespawnAttempts = 2
    private var saveTask: Task<Void, Never>?
    private var saveTaskID: UUID?
    private var needsFollowUpSave: Bool = false

    // Convenience accessors into shared runtime state.
    var turnState: TurnState { state.turnState }
    var messageQueue: MessageQueue { state.messageQueue }
    var streamingText: String? { state.streamingText }
    var lastTurnError: String? {
        get { state.lastTurnError }
        set { state.lastTurnError = newValue }
    }
    var stagedContext: String? {
        get { state.stagedContext }
        set { state.stagedContext = newValue }
    }
    var sessionContinuityNotice: String? {
        get { state.sessionContinuityNotice }
        set { state.sessionContinuityNotice = newValue }
    }
    /// Non-nil while first-message setup is running.
    var setupPhase: SetupPhase? {
        get { state.setupPhase }
        set { state.setupPhase = newValue }
    }

    // `SetupPhase` lives outside the VM so ConversationState can use it earlier.

    init(conversation: Conversation, agentsManager: any AgentsManager,
         runtimeStore: any ConversationRuntimeStore,
         modelContext: ModelContext, settingsService: SettingsService,
         worktreeManager: WorktreeManager, providerSetup: ProviderSetupService) {
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.modelContext = modelContext
        self.conversationModelID = conversation.persistentModelID
        self.settingsService = settingsService
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.state = runtimeStore.conversationState(for: conversation.id)
        subscribe()
    }

    /// Re-resolve models through this VM's `ModelContext` before mutating them.
    private func dbConversation() -> Conversation? {
        modelContext.model(for: conversationModelID) as? Conversation
    }

    private func dbThread() -> AgentThread? {
        dbConversation()?.thread
    }

    /// True only until the thread completes its persisted first-run setup.
    /// The centered pre-history Retry UI is intentionally not keyed off this alone:
    /// a cleanup-failure rollback can preserve `hasCompletedInitialSetup = true`
    /// so retry reuses the surviving worktree instead of creating a second one.
    var needsSetup: Bool {
        !(dbThread()?.hasCompletedInitialSetup ?? true)
    }

    /// Existing threads can still need respawn after relaunch, restore, or crash cleanup.
    private func needsRespawn() async -> Bool {
        guard !needsSetup else { return false }
        return !(await agentsManager.isRunning(conversationId: conversation.id))
    }

    /// Self-heal a persisted worktree-backed thread whose on-disk worktree vanished.
    /// This demotes the thread back into first-message setup so the next send can
    /// recreate the worktree instead of failing with a generic spawn error.
    private func repairMissingWorktreeIfNeeded() throws {
        guard let thread = dbThread(),
              thread.useWorktree,
              thread.hasCompletedInitialSetup,
              let worktreePath = thread.worktreePath,
              !FileManager.default.fileExists(atPath: worktreePath) else {
            return
        }
        if let branch = thread.branch,
           !thread.pendingCleanupBranches.contains(branch) {
            thread.pendingCleanupBranches.append(branch)
        }
        thread.branch = nil
        thread.worktreePath = nil
        thread.hasCompletedInitialSetup = false
        try modelContext.save()
    }

    /// Shared spawn config builder for setup, respawn, and reconfigure.
    private func makeSpawnConfig(
        workingDirectory overrideWorkingDirectory: String? = nil,
        initialPrompt: String? = nil
    ) throws -> AgentSpawnConfig {
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }
        let providerId = dbConversation.provider ?? settingsService.current.defaultProvider
        let workingDirectory = overrideWorkingDirectory
            ?? dbConversation.thread?.worktreePath
            ?? dbConversation.thread?.project?.path
        guard let workingDirectory, !workingDirectory.isEmpty else {
            throw AgentError.spawnFailed("Cannot spawn agent: no working directory")
        }
        return AgentSpawnConfig(
            providerId: providerId,
            workingDirectory: workingDirectory,
            permissionMode: dbConversation.thread?.permissionMode,
            model: state.selectedModel,
            effort: dbConversation.thread?.effort,
            initialPrompt: initialPrompt
        )
    }

    /// Shared pre-spawn provider setup path.
    private func prepareForSpawn(config: AgentSpawnConfig) async {
        let shouldAutoTrust = settingsService.current.autoTrustWorktrees
            && (dbThread()?.useWorktree ?? false)
        await providerSetup.prepareForSpawn(
            providerId: config.providerId,
            workingDirectory: config.workingDirectory,
            autoTrust: shouldAutoTrust
        )
    }

    /// Closes the pre-await reentrancy gap for setup, respawn, and send paths.
    private func withOutboundReservation<T>(_ body: () async throws -> T) async throws -> T {
        guard !state.isReconfiguringSession else {
            throw AgentError.spawnFailed("Session changes are still being applied")
        }
        guard !state.isSendingMessage else {
            throw AgentError.spawnFailed("Another message is already being sent")
        }
        state.isSendingMessage = true
        defer { state.isSendingMessage = false }
        return try await body()
    }

    func startAgent(config: AgentSpawnConfig) async throws {
        try await withOutboundReservation {
            try await startAgentReserved(config: config)
        }
    }

    private func startAgentReserved(config: AgentSpawnConfig) async throws {
        await prepareForSpawn(config: config)
        try await agentsManager.spawn(id: conversation.id, config: config)
        subscribe()
    }

    /// Shared outbound path for user messages that may need setup or respawn first.
    private func deliverMessageReserved(
        _ message: String,
        stagedContextOverride: String? = nil
    ) async throws {
        try repairMissingWorktreeIfNeeded()
        if needsSetup {
            try await setupAndStartReserved(message, stagedContextOverride: stagedContextOverride)
            return
        }
        if await needsRespawn() {
            try await startAgentReserved(config: makeSpawnConfig())
            state.respawnAttempts = 0
        }
        try await sendReserved(message, stagedContextOverride: stagedContextOverride)
    }

    /// First-message flow: worktree creation → spawn → send.
    func setupAndStart(_ message: String) async throws {
        try await withOutboundReservation {
            try await setupAndStartReserved(message)
        }
    }

    private func setupAndStartReserved(
        _ message: String,
        stagedContextOverride: String? = nil
    ) async throws {
        state.lastTurnError = nil
        guard let dbConversation = dbConversation(),
              let thread = dbConversation.thread,
              let project = thread.project else {
            throw AgentError.spawnFailed("No project associated with this thread")
        }
        var workingDir = project.path
        let worktreeSlug = Self.threadName(from: message) ?? thread.name

        // 1. Create worktree (if enabled)
        if thread.useWorktree {
            setupPhase = .creatingWorktree
            do {
                let info = try await worktreeManager.create(
                    projectPath: project.path,
                    threadName: worktreeSlug,
                    baseRef: project.baseRef,
                    remoteName: project.remoteName
                )
                thread.worktreePath = info.path
                thread.branch = info.branch
                workingDir = info.path
                try modelContext.save()
            } catch {
                if thread.useWorktree, let path = thread.worktreePath {
                    do {
                        try await worktreeManager.remove(
                            projectPath: project.path,
                            worktreePath: path,
                            branch: thread.branch
                        )
                        thread.worktreePath = nil
                        thread.branch = nil
                        try modelContext.save()
                    } catch {
                        state.lastTurnError = "Initial worktree setup failed and rollback cleanup/metadata clear also failed: \(error.localizedDescription)"
                    }
                }
                setupPhase = nil
                throw error
            }
        }

        // 2. Spawn agent
        setupPhase = .startingAgent
        do {
            try await startAgentReserved(config: makeSpawnConfig(workingDirectory: workingDir))
            thread.hasCompletedInitialSetup = true
            try modelContext.save()
            try await sendReserved(message, stagedContextOverride: stagedContextOverride)
        } catch let setupError {
            // Initial setup rollback must also restore `hasCompletedInitialSetup = false`.
            let preservedDraft = message
            let preservedSelectedModel = state.selectedModel
            let preservedStagedContext = state.stagedContext
            // Cancel VM-local tasks before destroying the failed runtime.
            subscriptionTask?.cancel()
            subscriptionTask = nil
            saveTask?.cancel()
            saveTask = nil
            saveTaskID = nil
            needsFollowUpSave = false
            do {
                try await agentsManager.destroyRuntime(conversationId: conversation.id)
            } catch let cleanupError {
                state.lastTurnError = "Initial setup failed: \(setupError.localizedDescription). Runtime cleanup also failed: \(cleanupError.localizedDescription)"
                setupPhase = nil
                throw AgentError.spawnFailed(state.lastTurnError ?? cleanupError.localizedDescription)
            }
            state = runtimeStore.conversationState(for: conversation.id)
            state.inputDraft = preservedDraft
            state.selectedModel = preservedSelectedModel
            state.stagedContext = preservedStagedContext
            thread.hasCompletedInitialSetup = false
            if thread.useWorktree, let path = thread.worktreePath {
                do {
                    try await worktreeManager.remove(
                        projectPath: project.path, worktreePath: path, branch: thread.branch
                    )
                    thread.worktreePath = nil
                    thread.branch = nil
                    try modelContext.save()
                } catch {
                    thread.hasCompletedInitialSetup = true
                    do {
                        try modelContext.save()
                        // `needsSetup` now stays false on purpose so the next retry respawns
                        // against this preserved worktree. The centered Retry UI is instead
                        // owned by ChatView's no-history-yet error state.
                        state.lastTurnError = "Initial setup failed and rollback worktree cleanup also failed: \(error.localizedDescription). The existing worktree was preserved, so retry will reuse it instead of creating a second worktree."
                    } catch {
                        state.lastTurnError = "Initial setup failed, rollback cleanup failed, and preserved thread metadata could not be saved: \(error.localizedDescription)"
                    }
                }
            } else {
                do {
                    try modelContext.save()
                } catch {
                    state.lastTurnError = "Initial spawn failed and rollback metadata reset also failed: \(error.localizedDescription)"
                }
            }
            setupPhase = nil
            throw setupError
        }
        setupPhase = nil
    }

    private func subscribe() {
        subscriptionTask?.cancel()
        let token = UUID()
        state.activeSubscriptionToken = token
        subscriptionTask = Task { @MainActor in
            guard let subscription = await agentsManager.subscribe(
                conversationId: conversation.id,
                afterIndex: state.lastPersistedEventIndex
            ) else {
                guard state.activeSubscriptionToken == token else { return }
                state.activeBufferGeneration = nil
                return
            }
            guard state.activeSubscriptionToken == token else { return }
            state.activeBufferGeneration = subscription.generation
            // Replay from the last persisted global index so reconnects never skip unsaved events.
            for await event in subscription.stream {
                guard state.activeSubscriptionToken == token else { return }
                state.lastObservedEventIndex += 1
                handleEvent(event)
            }
            // Only a real EOF from the active subscription performs fallback cleanup.
            guard !Task.isCancelled, state.activeSubscriptionToken == token else { return }
            state.turnState.endTurn()
            state.clearStreamingText()
        }
    }

    /// `.tokens` is the normal queue-drain boundary for long-lived providers.
    private func handleTurnCompleted() {
        guard state.messageQueue.peekNext() != nil else {
            state.turnState.endTurn()
            return
        }
        Task { @MainActor in
            guard state.inFlightQueuedMessageID == nil else { return }
            guard let next = state.messageQueue.peekNext() else {
                state.turnState.endTurn()
                return
            }
            state.inFlightQueuedMessageID = next.id
            defer {
                if state.inFlightQueuedMessageID == next.id {
                    state.inFlightQueuedMessageID = nil
                }
            }
            do {
                try await withOutboundReservation {
                    if await needsRespawn() {
                        guard state.respawnAttempts < Self.maxRespawnAttempts else {
                            state.lastTurnError = "Agent process keeps crashing — queued message paused"
                            state.respawnAttempts = 0
                            state.turnState.endTurn()
                            return
                        }
                        state.respawnAttempts += 1
                    }
                    try await deliverMessageReserved(next.text, stagedContextOverride: next.stagedContext)
                    state.messageQueue.remove(id: next.id)
                    state.respawnAttempts = 0
                }
            } catch {
                state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
                state.turnState.endTurn()
            }
        }
    }

    /// Persist the local user message only after a successful transport write.
    func send(_ message: String, stagedContextOverride: String? = nil) async throws {
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before sending a new one")
        }
        try await withOutboundReservation {
            try await deliverMessageReserved(message, stagedContextOverride: stagedContextOverride)
        }
    }

    /// VM-local persistence helper for user-authored stdin writes.
    private func insertLocalUserMessage(
        _ message: String,
        into dbConversation: Conversation,
        shouldAutoNameThread: Bool
    ) {
        let record = ConversationEventRecord(type: "message", role: "user", content: message)
        record.conversation = dbConversation
        record.conversationId = dbConversation.id
        modelContext.insert(record)
        // Patch the grouped-history cache immediately so the pre-history chat shell
        // cannot briefly fall back to the centered hero while the coalesced save / @Query
        // merge catches up with the already-successful stdin write.
        state.grouper.appendLocalUserMessage(id: record.id, text: message)
        if shouldAutoNameThread,
           settingsService.current.autoGenerateNames,
           dbConversation.thread?.name == "New thread",
           let name = Self.threadName(from: message) {
            dbConversation.thread?.name = name
        }
        scheduleSave()
    }

    private func sendReserved(_ message: String, stagedContextOverride: String? = nil) async throws {
        let transportMessage: String
        if let context = stagedContextOverride ?? state.stagedContext {
            transportMessage = context + "\n\n" + message
        } else {
            transportMessage = message
        }
        guard let dbConversation = dbConversation() else {
            throw AgentError.spawnFailed("Conversation no longer exists")
        }
        state.lastTurnError = nil
        try await agentsManager.sendMessage(transportMessage, conversationId: conversation.id)
        if stagedContextOverride == nil {
            state.stagedContext = nil
        }
        state.turnState.beginTurn()
        insertLocalUserMessage(message, into: dbConversation, shouldAutoNameThread: true)
    }

    func queueOrSend(_ message: String) async throws {
        if state.turnState.isActive || state.isSendingMessage || state.messageQueue.peekNext() != nil {
            state.messageQueue.enqueue(message, stagedContext: state.stagedContext)
            // Consume the banner once its snapshot is captured in a queued entry.
            state.stagedContext = nil
        } else {
            try await withOutboundReservation {
                try await deliverMessageReserved(message)
            }
        }
    }

    /// User-initiated respawn path for an existing conversation.
    private func respawnAndSend(_ message: String) async throws {
        try await withOutboundReservation {
            try await deliverMessageReserved(message)
        }
    }

    private func respawnAndSendReserved(_ message: String) async throws {
        try await deliverMessageReserved(message)
    }

    /// Mid-turn steering for providers that accept stdin while busy.
    func steer(_ message: String) async throws {
        guard state.turnState.isActive else {
            throw AgentError.spawnFailed("Wait for the agent to be actively working before steering")
        }
        try await withOutboundReservation {
            guard let dbConversation = dbConversation() else {
                throw AgentError.spawnFailed("Conversation no longer exists")
            }
            state.lastTurnError = nil
            try await agentsManager.sendMessage(message, conversationId: conversation.id)
            insertLocalUserMessage(message, into: dbConversation, shouldAutoNameThread: false)
        }
    }

    /// Answer an AskUserQuestion prompt once the turn is idle, then persist the summary.
    func answerPrompt(promptId: String, answers: [(question: String, answer: String)]) async throws -> String {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn to finish before answering the prompt")
        }
        guard state.messageQueue.peekNext() == nil else {
            throw AgentError.spawnFailed("Resolve the queued message at the head of the queue before answering the prompt")
        }
        let message = Self.formatPromptAnswers(answers: answers)
        let summary = Self.promptSummary(answers: answers)
        try await withOutboundReservation {
            try await deliverMessageReserved(message)
        }
        let conversationId = conversation.id
        let promptEvents = try? modelContext.fetch(FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate {
                $0.conversationId == conversationId &&
                $0.type == "tool_call" &&
                $0.toolId == promptId &&
                $0.toolName == "AskUserQuestion"
            }
        ))
        if let promptRecord = promptEvents?.last {
            promptRecord.content = summary
            do {
                try modelContext.save()
                // Same-record mutation: patch the block in place instead of full regroup.
                state.grouper.markPromptAnswered(promptId: promptId, summary: summary)
            } catch {
                // Best-effort only; the live block already switched locally.
            }
        }
        return summary
    }

    /// Reconfigure spawn-time flags while preserving local durable history.
    /// Queued messages remain queued after a successful reconfigure; v1 requires the
    /// user to retry the queued head explicitly rather than auto-sending it under the
    /// new session settings.
    func reconfigureSession(config: AgentSpawnConfig) async throws {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before applying session changes")
        }
        guard !state.isReconfiguringSession else { return }
        state.isReconfiguringSession = true
        defer { state.isReconfiguringSession = false }
        // Flush old-session saves before resetting replay cursors.
        await flushPendingSaveIfNeeded()
        await prepareForSpawn(config: config)
        try await agentsManager.reconfigureSession(
            conversationId: conversation.id, config: config
        )
        state.showPermissionBanner = false
        state.lastPermissionDeniedToolNames = []
        state.lastObservedEventIndex = 0
        state.lastPersistedEventIndex = 0
        state.activeBufferGeneration = nil
        // Preserve durable grouped history; clear only session-scoped live caches.
        state.grouper.resetInFlightStateForNewSession()
        subscribe()
    }

    /// Single mutation funnel for persisted history → grouped ChatItems.
    func rebuildChatItemsIfNeeded(from events: [ConversationEventRecord], forceFullRebuild: Bool = false) {
        state.grouper.update(events: events, forceFullRebuild: forceFullRebuild)
    }

    func removeQueuedMessage(id: UUID) {
        guard state.inFlightQueuedMessageID != id else { return }
        let removed = state.messageQueue.remove(id: id)
        if let restoredContext = removed?.stagedContext,
           state.stagedContext == nil,
           !state.messageQueue.pending.contains(where: { $0.stagedContext != nil }) {
            state.stagedContext = restoredContext
        }
    }

    /// Explicit retry path for a queued head that previously failed during auto-send.
    func retryNextQueuedMessage() async throws {
        guard !state.turnState.isActive, !state.isSendingMessage else {
            throw AgentError.spawnFailed("Wait for the current turn/send to finish before retrying the queued message")
        }
        guard state.inFlightQueuedMessageID == nil else { return }
        guard let next = state.messageQueue.peekNext() else { return }
        state.inFlightQueuedMessageID = next.id
        defer {
            if state.inFlightQueuedMessageID == next.id {
                state.inFlightQueuedMessageID = nil
            }
        }
        do {
            try await withOutboundReservation {
                try await deliverMessageReserved(next.text, stagedContextOverride: next.stagedContext)
                state.messageQueue.remove(id: next.id)
                state.respawnAttempts = 0
            }
        } catch {
            state.lastTurnError = "Queued message failed to send: \(error.localizedDescription)"
            throw error
        }
    }

    /// Stop is request-based: stay busy until `.tokens` or real EOF arrives.
    func cancel() async {
        await agentsManager.cancelTurn(conversationId: conversation.id)
    }

    /// Persist durable events, keep local user messages local, and treat `.tokens` as the
    /// normal turn-complete signal. Transient sub-agent control events update the grouper
    /// live but do not persist.
    private func handleEvent(_ event: ConversationEvent) {
        switch event {
        case .messageChunk(let text, let parentToolUseId):
            guard parentToolUseId == nil else { return }
            state.appendStreamingChunk(text)
            return  // Not persisted — full message replaces chunks

        case .message(let role, _, _) where role == "user":
            // User messages are inserted locally by `send()`.
            return

        case .message(let role, _, _) where role == "assistant":
            state.clearStreamingText()

        case .tokens(_, _, _, let isError, let stopReason, _, _, let permissionDenials):
            // `.tokens` is the normal terminal turn signal.
            state.clearStreamingText()
            if isError {
                state.lastTurnError = stopReason ?? "Agent turn failed"
            }
            state.lastPermissionDeniedToolNames = Set(permissionDenials.map(\.toolName))
            state.showPermissionBanner = !permissionDenials.isEmpty
            if !isError && permissionDenials.isEmpty {
                handleTurnCompleted()
            } else {
                state.turnState.endTurn()
            }

        case .stop(_):
            state.turnState.endTurn()  // Fallback only; queue drain stays tied to `.tokens`.

        case .subAgentStarted(_, _, _), .subAgentProgress(_, _, _, _, _, _), .subAgentCompleted(_, _, _, _, _):
            state.grouper.handleSubAgentControl(event)
            return  // Not persisted; inner events and Agent tool_result are durable.

        case .notification(_, _), .error(_):
            break  // Persisted below

        default:
            break
        }

        guard let dbConversation = dbConversation(),
              let record = event.toRecord(conversation: dbConversation)
        else { return }
        modelContext.insert(record)
        scheduleSave()
    }

    /// Coalesce saves so `@Query` re-evaluation stays bounded. Snapshot the observed index
    /// and generation when scheduling so an older VM can only advance the replay boundary
    /// for the exact range its own `ModelContext` flushed.
    private func scheduleSave() {
        guard saveTask == nil else {
            needsFollowUpSave = true
            return
        }
        let observedIndexSnapshot = state.lastObservedEventIndex
        let generationSnapshot = state.activeBufferGeneration
        let taskID = UUID()
        saveTaskID = taskID
        saveTask = Task { @MainActor in
            let delayMs = state.turnState.isActive ? 350 : 150
            do {
                try await Task.sleep(for: .milliseconds(delayMs))
                try Task.checkCancellation()
            } catch {
                guard saveTaskID == taskID else { return }
                saveTask = nil
                saveTaskID = nil
                return
            }
            do {
                try modelContext.save()
                // Advance replay only after a successful save.
                guard state.activeBufferGeneration == generationSnapshot else {
                    guard saveTaskID == taskID else { return }
                    saveTask = nil
                    saveTaskID = nil
                    return
                }
                guard !Task.isCancelled else {
                    guard saveTaskID == taskID else { return }
                    saveTask = nil
                    saveTaskID = nil
                    return
                }
                state.lastPersistedEventIndex = max(state.lastPersistedEventIndex, observedIndexSnapshot)
                if let generationSnapshot {
                    await agentsManager.markPersisted(
                        conversationId: conversation.id,
                        generation: generationSnapshot,
                        upTo: observedIndexSnapshot
                    )
                }
            } catch {
                // Keep the older persisted cursor so reconnects replay the unsaved tail.
            }
            guard saveTaskID == taskID else { return }
            saveTask = nil
            saveTaskID = nil
            if needsFollowUpSave {
                needsFollowUpSave = false
                scheduleSave()
            }
        }
    }

    /// Used by reconfigure before replay cursors are reset.
    private func flushPendingSaveIfNeeded() async {
        guard let saveTask else { return }
        await saveTask.value
    }

    deinit {
        subscriptionTask?.cancel()
        saveTask?.cancel()
    }
}
```

---

Usage notes plus the `ConversationViewModel` regression-test matrix continue in [Supplement: ConversationViewModel Behaviors](supplement-conversation-viewmodel-behaviors.md).
