# Part 4c: Chat View

Chat view ownership, rendering structure, banner stack, and composer integration. Composer-state details and live progress continue in the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md). Continues from Part 4b.

## Chat View Architecture

The primary content view for a thread is a **native SwiftUI chat interface** driven by the `ConversationEvent` stream.

### ConversationView (Entry Point)

`ConversationView` creates the `ConversationViewModel` (`Skep/ViewModels/ConversationViewModel.swift`) and passes it to `ChatView`:

```swift
struct ConversationView: View {  // Skep/Views/Chat/ConversationView.swift
    let conversation: Conversation
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let modelContext: ModelContext
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let fileListManager: FileListManager
    let loadSkillCompletions: () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Bindable var appState: AppState
    @State private var viewModel: ConversationViewModel

    private var activeWorkingDirectory: String? {
        conversation.thread?.worktreePath ?? conversation.thread?.project?.path
    }

    private var composerCapabilities: ComposerCapabilities {
        let providerId = conversation.provider ?? settingsService.current.defaultProvider
        let provider = providerRegistry.provider(for: providerId)
        return ComposerCapabilities(
            supportedEffortLevels: provider?.supportedEffortLevels ?? [],
            supportedPermissionModes: provider?.supportedPermissionModes ?? [],
            suggestedWriteEscalationMode: provider?.suggestedWriteEscalationMode,
            writeEscalationEligibleTools: provider?.writeEscalationEligibleTools ?? [],
            supportsMidTurnSteering: provider?.supportsMidTurnSteering ?? false
        )
    }

    init(
        conversation: Conversation,
        agentsManager: any AgentsManager,
        runtimeStore: any ConversationRuntimeStore,
        modelContext: ModelContext,
        settingsService: SettingsService,
        providerRegistry: ProviderRegistry,
        worktreeManager: WorktreeManager,
        providerSetup: ProviderSetupService,
        fileListManager: FileListManager,
        loadSkillCompletions: @escaping () async -> [Skill],
        diffViewModel: DiffViewerViewModel,
        appState: AppState
    ) {
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.modelContext = modelContext
        self.settingsService = settingsService
        self.providerRegistry = providerRegistry
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.fileListManager = fileListManager
        self.loadSkillCompletions = loadSkillCompletions
        self.diffViewModel = diffViewModel
        self.appState = appState
        self._viewModel = State(initialValue: ConversationViewModel(
            conversation: conversation,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            modelContext: modelContext,
            settingsService: settingsService,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup
        ))
    }

    var body: some View {
        ChatView(
            viewModel: viewModel,
            conversation: conversation,
            diffViewModel: diffViewModel,
            composerCapabilities: composerCapabilities,
            loadFileCompletions: {
                guard let path = conversation.thread?.worktreePath ?? conversation.thread?.project?.path else {
                    return []
                }
                return await fileListManager.files(for: path)
            },
            loadSkillCompletions: loadSkillCompletions,
            appState: appState
        )
            .task {
                // Warm the file list cache so the first @-mention autocomplete is instant.
                if let path = activeWorkingDirectory {
                    await fileListManager.warmCache(for: path)
                }
            }
            .onChange(of: activeWorkingDirectory) { _, newPath in
                guard let newPath else { return }
                Task {
                    // First-message setup can switch the selected thread from project root
                    // to a newly created worktree. Warm the new file cache immediately and,
                    // if this thread is still selected, rebind the shared diff view model so
                    // the right pane / changed-files strip stop pointing at the old directory.
                    await fileListManager.warmCache(for: newPath)
                    guard case .thread(let selectedThread) = appState.selectedSidebarItem,
                          selectedThread.persistentModelID == conversation.thread?.persistentModelID,
                          let thread = conversation.thread else {
                        return
                    }
                    let baseRef = thread.project?.baseRef ?? "main"
                    let remoteName = thread.project?.remoteName
                    let conversationIds = Set(thread.conversations.map(\.id))
                    await diffViewModel.switchToDirectory(
                        newPath,
                        baseRef: baseRef,
                        remoteName: remoteName,
                        conversationIds: conversationIds
                    )
                }
            }
            .onChange(of: appState.pendingDiffAction) { _, request in
                guard let request,
                      request.conversationID == conversation.persistentModelID else {
                    return
                }
                Task {
                    let priorDraft = viewModel.state.inputDraft
                    defer {
                        if appState.pendingDiffAction?.id == request.id {
                            appState.pendingDiffAction = nil
                        }
                    }
                    guard appState.pendingDiffAction?.id == request.id,
                          case .thread(let selectedThread) = appState.selectedSidebarItem,
                          selectedThread.persistentModelID == conversation.thread?.persistentModelID,
                          appState.selectedConversation(in: selectedThread)?.persistentModelID == conversation.persistentModelID else {
                        return
                    }
                    do {
                        try await viewModel.queueOrSend(request.message)
                    } catch {
                        viewModel.state.inputDraft = priorDraft.isEmpty ? request.message : priorDraft
                        if viewModel.lastTurnError == nil {
                            viewModel.lastTurnError = error.localizedDescription
                        }
                    }
                }
            }
    }
}
```

Dependency boundary: `ConversationView` is an owning view, but it is **not** a secondary service locator. The layout layer (`ContentView` / `ThreadDetailView`) remains the composition root and resolves Knit services there; the chat subtree receives only the specific collaborators or async loaders it needs. That includes the stable composition-owned write `ModelContext` passed in from above rather than a fresh `resolver.modelContext()` lookup during each render. This keeps `ConversationView`, `ChatView`, and `ChatInputField` testable and prevents hidden scope expansion from a long-lived `Resolver` drifting deeper into the view tree.

`ConversationView` is also the boundary where provider registry metadata becomes a small render-only value for the chat subtree. It resolves the active provider once (`conversation.provider ?? settings.defaultProvider`) and passes a `ComposerCapabilities` snapshot into `ChatView` / `ChatInputField`, rather than letting those views reach into `ProviderRegistry` or `Resolver` directly.

`ConversationView` renders a single selected conversation. The thread-level tab bar and side-conversation creation live one level up in `ThreadDetailView` (see [Part 4a: Layout](part4a-layout.md)), which chooses the active conversation from the pure `AppState.selectedConversation(in:)` resolver and repairs stale bookmarks via `repairSelectedConversationIfNeeded(for:)` in effects rather than in `body`. It then presents `ConversationView(...).id(conversation.id)`. The explicit identity forces SwiftUI to reinitialize the `@State`-backed `ConversationViewModel` when the selected conversation changes. Without it, SwiftUI can reuse the old VM instance and leave the view subscribed to the wrong conversation.

`ConversationView` is also the consumer for `AppState.pendingDiffAction`. That one-shot request is emitted by the global `DiffViewerPane` owner in `ContentView`, scoped to a specific `conversation.persistentModelID`, and forwarded through `viewModel.queueOrSend()` only by the matching visible conversation. It is intentionally cancel-on-navigation: `ContentView` clears the request when middle-pane navigation stops targeting the snapshotted conversation, `ThreadDetailView` clears it when same-thread tab switching changes the selected conversation before delivery, and the consumer re-checks both the live request ID and the currently selected thread/conversation immediately before calling `queueOrSend()`. That last re-check closes the small task-scheduling gap where the request could otherwise still send after navigation already canceled it.

`ConversationView` also watches its thread's **effective working directory** (`worktreePath ?? project.path`). This closes an important lifecycle gap in the later phases: when first-message setup creates a worktree for the currently selected thread, the chat layer warms `FileListManager` for that new path and rebinds the shared `DiffViewerViewModel` immediately instead of waiting for the user to reselect the thread. That keeps the right pane, changed-files strip, and `@` autocomplete aligned with the real working directory as soon as setup completes.

`ChatView` itself stays render-only. It forwards UI intents (`rebuildChatItemsIfNeeded`, `removeQueuedMessage`, `retryNextQueuedMessage`, submit/steer/stop) to `ConversationViewModel` rather than mutating `ConversationState` directly. Persisted thread-setting changes (effort / permission mode) still follow the same owner boundary: the owning chat layer must run them through one small optimistic-with-revert helper that saves via the active `ModelContext` instead of relying on bare `conversation.thread?... = ...` binding setters.

The chat/composer boundary is intentionally narrow. `ChatView` receives only render data plus async loaders for file and skill completions; it does not reach back into `Resolver`, `SkillsService`, or `FileListManager` on its own. That preserves the step-8 DI boundary: the layout layer composes services, while the chat subtree consumes explicit collaborators.

The focused `ChatView` snippet below keeps comments short on purpose. The non-obvious invariants — pre-history content detection, queued-message follow mode, banner ordering, and the owner-supplied dropdown bindings/loaders — are described in the surrounding prose and supplements instead of being buried in long inline comments.

When `viewModel.state.showPermissionBanner` is true, `ChatView` renders a permission banner between the scroll area and `ChatInputField`. The banner always offers dismiss (`showPermissionBanner = false`) and may also offer a provider-driven escalation action when the active provider definition supplies `suggestedWriteEscalationMode` **and** the latest denied tool names intersect that provider's `writeEscalationEligibleTools`. In v1 Claude that means denied `Write` / `Edit` / `MultiEdit` turns can offer **Auto-Edit** (`acceptEdits`), while denied Bash or AskUserQuestion turns stay dismiss-only. The escalation action uses the same optimistic-with-revert flow as the permission dropdown: update `thread.permissionMode`, call `viewModel.reconfigureSession(...)` when a session is already running, clear the banner on success, and restore the previous mode if reconfigure fails so the visible badge/dropdown keep matching the actual live session. Providers without a suggested escalation mode, or denials outside their eligible-tool set, keep the banner dismiss-only. The banner's action buttons follow the same busy gating as the dropdowns: disable the reconfigure path while a turn is active, an outbound send is reserved, or another reconfigure is already in flight.

When the conversation has no persisted or live chat content yet, `ChatView` also owns the empty-thread hero / setup state from Part 3a. That shell is driven by the absence of event-backed/live content plus `viewModel.setupPhase` and `viewModel.lastTurnError`, not by `viewModel.needsSetup` alone. This keeps first-message rollback failures that intentionally preserve worktree metadata (`hasCompletedInitialSetup = true`) in the same centered Retry owner until the first successful turn actually produces history:
- **Fresh thread, no setup or pre-history error in progress** → show the centered "Let's build" hero and the normal input bar.
- **Initial setup running** (`setupPhase != nil`) → replace the hero with the progress indicator ("Creating worktree" / "Starting agent") and disable submission controls until the first spawn finishes.
- **First outbound/setup failed before any history exists** (`lastTurnError != nil` while events, grouped items, and `streamingText` are still empty) → show the centered setup-error card with a "Retry" button that re-runs `queueOrSend()` using the restored `inputDraft`. Depending on the preserved thread metadata, that retry may either re-enter first-message setup or respawn against the preserved worktree.

Once there is persisted chat history, `lastTurnError` no longer uses the centered empty-thread state. Instead, `ChatView` renders it as a dismissible inline banner between the scroll area and the input area so the existing conversation stays visible. That banner is cleared either by explicit dismissal or when a new setup/send/steer attempt begins, so stale failures do not survive a successful retry.

If the runtime had to restart with a fresh provider session because Claude's resumable artifact was missing, `ChatView` also renders a dismissible continuity warning in that same banner stack. The warning must say that local conversation history is still visible in Skep, but the live provider context restarted fresh.

Banner boundary: the shared `InlineBanner` from [Part 4e](part4e-screens-and-lifecycle.md) covers plain dismissible errors/warnings such as `lastTurnError` and `sessionContinuityNotice`. The reconfigure-progress row and permission-denial surface stay as chat-local helpers because they add non-dismissible progress or provider CTA behavior that should not be pushed into the shared component.

`ChatView` also receives `AppState` because the compact changed-files rows above the input need to do more than render summary data: tapping `[Diff]` must toggle `appState.isRightPaneVisible = true` and focus the shared `DiffViewerViewModel` on the selected file instead of being a dead-end button. During a cross-directory thread switch, the shared diff VM blanks that summary first, so the newly shown chat cannot accidentally open a stale file from the previously selected thread.

### EmptyThreadState

`EmptyThreadState` is a small render-only helper used by `ChatView` for the three pre-history states above. It keeps the setup/progress/error layout out of the main scroll-view code path and gives the later Phase 6 chat snapshot matrix a concrete owner.

```swift
struct EmptyThreadState: View {  // Skep/Views/Chat/EmptyThreadState.swift
    let showsRetryState: Bool
    let setupPhase: SetupPhase?
    let error: String?
    let draft: String
    let onRetry: () -> Void
}

struct ComposerCapabilities: Sendable {  // Skep/Views/Chat/ComposerCapabilities.swift
    let supportedEffortLevels: [String]
    let supportedPermissionModes: [PermissionModeOption]
    let suggestedWriteEscalationMode: String?
    let writeEscalationEligibleTools: Set<String>
    let supportsMidTurnSteering: Bool
}
```

Rendering rules:
- `setupPhase == nil && !showsRetryState` → show the static "Let's build" hero from Part 3a.
- `setupPhase == .creatingWorktree` / `.startingAgent` → show the spinner + phase label.
- `showsRetryState` → show the centered setup-error card with Retry and optional install guidance CTA. This is keyed to the lack of persisted/live chat content, so it still applies when retry will respawn against a preserved worktree instead of recreating one.

### ChatView (Structure)

```swift
struct ChatView: View {  // Skep/Views/Chat/ChatView.swift
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let diffViewModel: DiffViewerViewModel
    let composerCapabilities: ComposerCapabilities
    let loadFileCompletions: () async -> [String]
    let loadSkillCompletions: () async -> [Skill]
    @Bindable var appState: AppState
    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing: Bool = true

    private var isPreHistorySetupInFlight: Bool {
        !hasVisibleChatContent && viewModel.setupPhase != nil
    }

    private var hasVisibleChatContent: Bool {
        !events.isEmpty || !viewModel.state.grouper.items.isEmpty || viewModel.streamingText != nil
    }

    private var showsCenteredPreHistoryRetry: Bool {
        !hasVisibleChatContent && viewModel.setupPhase == nil && viewModel.lastTurnError != nil
    }

    private var composerIsBusy: Bool {
        viewModel.turnState.isActive || viewModel.state.isSendingMessage
    }

    private var promptSubmissionIsBusy: Bool {
        composerIsBusy || viewModel.state.isReconfiguringSession
    }

    private var composerMode: ComposerMode {
        if isPreHistorySetupInFlight {
            return .progressOnly(.initialSetup)
        }
        if viewModel.state.isReconfiguringSession {
            return .progressOnly(.reconfiguringSession)
        }
        if composerIsBusy {
            return .busy(canStop: viewModel.turnState.isActive)
        }
        return .idle
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        diffViewModel: DiffViewerViewModel,
        composerCapabilities: ComposerCapabilities,
        loadFileCompletions: @escaping () async -> [String],
        loadSkillCompletions: @escaping () async -> [Skill],
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.diffViewModel = diffViewModel
        self.composerCapabilities = composerCapabilities
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.appState = appState
        let conversationId = conversation.id
        _events = Query(
            filter: #Predicate { $0.conversationId == conversationId },
            sort: \.timestamp
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasVisibleChatContent {
                EmptyThreadState(
                    showsRetryState: showsCenteredPreHistoryRetry,
                    setupPhase: viewModel.setupPhase,
                    error: showsCenteredPreHistoryRetry ? viewModel.lastTurnError : nil,
                    draft: viewModel.state.inputDraft,
                    onRetry: {
                        let message = viewModel.state.inputDraft
                        Task {
                            do {
                                try await viewModel.queueOrSend(message)
                            } catch {
                                // Keep the VM's more specific rollback message.
                                if viewModel.lastTurnError == nil {
                                    viewModel.lastTurnError = error.localizedDescription
                                }
                            }
                        }
                    }
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.state.grouper.items) { item in
                                switch item {
                                case .userMessage(_, let text):
                                    UserBubble(text: text)
                                case .assistantMessage(_, let text):
                                    AssistantBubble(markdown: text)
                                case .workingBlock(_, let tools):
                                    WorkingBlock(tools: tools)
                                case .subAgentBlock(_, let agents):
                                    SubAgentBlock(agents: agents)
                                case .taskListBlock(_, let tasks):
                                    TaskListBlock(tasks: tasks)
                                case .promptBlock(_, let prompt):
                                    PromptBlock(prompt: prompt, isBusy: promptSubmissionIsBusy) { answers in
                                        do {
                                            return try await viewModel.answerPrompt(promptId: prompt.id, answers: answers)
                                        } catch {
                                            if viewModel.lastTurnError == nil {
                                                viewModel.lastTurnError = "Failed to send answer: \(error.localizedDescription)"
                                            }
                                            return nil
                                        }
                                    }
                                case .thinking(_, let text):
                                    ThinkingBlock(text: text)
                                case .error(_, let message):
                                    ErrorBanner(message: message)
                                }
                            }

                            if let streamingText = viewModel.streamingText {
                                StreamingBubble(text: streamingText)
                                    .id("streaming")
                            }

                            ForEach(viewModel.messageQueue.pending) { entry in
                                QueuedMessageBubble(
                                    text: entry.text,
                                    showsStagedContext: entry.stagedContext != nil,
                                    showsRetry: viewModel.state.inFlightQueuedMessageID == nil
                                        && viewModel.messageQueue.peekNext()?.id == entry.id
                                        && !viewModel.state.turnState.isActive,
                                    isDismissDisabled: viewModel.state.inFlightQueuedMessageID == entry.id,
                                    onRetry: {
                                        Task { try? await viewModel.retryNextQueuedMessage() }
                                    },
                                    onDismiss: {
                                    viewModel.removeQueuedMessage(id: entry.id)
                                    }
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                    }
                    .transaction { t in
                        if viewModel.turnState.isActive { t.disablesAnimations = true }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                        return distanceFromBottom < 60
                    } action: { _, isNearBottom in
                        isFollowing = isNearBottom
                    }
                    .onChange(of: events.count) {
                        viewModel.rebuildChatItemsIfNeeded(from: events)
                        if isFollowing {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.messageQueue.pending.count) {
                        guard isFollowing else { return }
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                    .onChange(of: viewModel.streamingText) {
                        guard isFollowing else { return }
                        let now = Date()
                        if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                            lastScrollTime = now
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        viewModel.rebuildChatItemsIfNeeded(from: events)
                    }
                    .onChange(of: viewModel.turnState.isActive) { _, isActive in
                        if isActive { isFollowing = true }
                    }
                    .overlay(alignment: .bottom) {
                        if !isFollowing && viewModel.turnState.isActive {
                            Button {
                                isFollowing = true
                                proxy.scrollTo("chat-bottom", anchor: .bottom)
                            } label: {
                                Label("New messages", systemImage: "arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .padding(.bottom, 8)
                        }
                    }
                }
            }

            if let lastTurnError = viewModel.lastTurnError,
               !showsCenteredPreHistoryRetry {
                InlineBanner(message: lastTurnError, severity: .error) {
                    viewModel.lastTurnError = nil
                }
            }

            if viewModel.state.isReconfiguringSession {
                ReconfigureStatusBanner(message: "Applying session changes...")
            }

            if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
                InlineBanner(message: sessionContinuityNotice, severity: .warning) {
                    viewModel.sessionContinuityNotice = nil
                }
            }

            if viewModel.state.showPermissionBanner {
                PermissionBanner(...)
            }

            if let stagedContext = viewModel.stagedContext {
                StagedContextBanner(context: stagedContext) {
                    viewModel.stagedContext = nil
                }
            }

            ChatInputField(
                text: Bindable(viewModel.state).inputDraft,
                mode: composerMode,
                onSubmit: {
                    let message = viewModel.state.inputDraft
                    viewModel.state.inputDraft = ""
                    Task {
                        do {
                            try await viewModel.queueOrSend(message)
                        } catch {
                            // Restore the draft so the user doesn't lose their message.
                            viewModel.state.inputDraft = message
                            if viewModel.lastTurnError == nil {
                                viewModel.lastTurnError = error.localizedDescription
                            }
                        }
                    }
                },
                onSteer: {
                    let message = viewModel.state.inputDraft
                    viewModel.state.inputDraft = ""
                    Task {
                        do {
                            try await viewModel.steer(message)
                        } catch {
                            viewModel.state.inputDraft = message
                            if viewModel.lastTurnError == nil {
                                viewModel.lastTurnError = "Steer failed: \(error.localizedDescription)"
                            }
                        }
                    }
                },
                onStop: {
                    Task { await viewModel.cancel() }
                },
                selectedModel: selectedModelBinding,
                selectedEffort: selectedEffortBinding,
                selectedPermissionMode: selectedPermissionModeBinding,
                supportedPermissionModes: composerCapabilities.supportedPermissionModes,
                supportedEffortLevels: composerCapabilities.supportedEffortLevels,
                supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions
            )
        }
    }
}
```

In that focused snippet, `ReconfigureStatusBanner`, `PermissionBanner`, and `StagedContextBanner` are small chat-local render helpers, not new app-wide shared components. Likewise, `selectedModelBinding`, `selectedEffortBinding`, and `selectedPermissionModeBinding` are the owner-supplied bindings defined in the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md).

`hasVisibleChatContent` intentionally counts the launch-scoped grouped-history cache as real content, not just persisted `@Query` rows. `ConversationViewModel.insertLocalUserMessage(...)` patches `state.grouper` immediately after a successful stdin write, before the later coalesced SwiftData save finishes. That closes the first-turn save-gap bug where the centered "Let's build" shell could otherwise briefly reappear after `setupPhase` cleared but before the local user message merged back through `@Query`.

The query intentionally filters on the indexed denormalized `conversationId` field rather than a relationship join, and it captures `conversation.id` into a local first so the SwiftData `#Predicate` macro does not have to chase a property-access chain on a captured model reference.

Follow mode anchors to `chat-bottom`, which sits after both the streaming bubble and queued-message region. `events.count` remains the incremental regroup trigger because prompt-answer mutations can update an existing persisted row without changing the row count; those same-row updates are patched from the VM after save instead of waiting for a count change.

Between the scroll area and `ChatInputField`, `ChatView` renders inline surfaces in a fixed order: `lastTurnError` banner, reconfigure-progress banner, session-continuity warning, permission-mode banner, then the staged-context banner from Part 2f. This keeps action-oriented banners close to the input while preserving the existing chat history.

Busy-turn editability is still a hard UI invariant: the composer stays editable while the agent is busy so users can queue or steer. Only the submit semantics change. The disabled composer states are the pre-history setup flow and fork-session reconfigure path, where another outbound action would overlap setup or target a process that is actively being replaced.

Concrete stack sketch:

```text
Scrollable chat history
last-turn error banner (if any)
"Applying session changes..." banner (if reconfiguring)
session-continuity warning (if the provider had to restart fresh)
permission banner (if the last turn hit a denial)
staged-context banner (if the next send is carrying hidden context)
compact changed-files strip (if diff summary exists for this thread)
ChatInputField
```

One common mixed-state example:

- The agent hits a write denial, so the permission banner appears.
- The user then queues a follow-up while a staged-context banner is visible.
- The queued bubble keeps the `📎` marker, the live staged-context banner disappears immediately, and the permission banner stays above the composer until the user dismisses it or a successful reconfigure clears it.

All chat-layer `catch` blocks above are fallback owners only: they restore drafts or complete one-shot UI cleanup, but they must only synthesize `lastTurnError` when the VM has not already set a more specific recovery message.

**Snapshot tests for `ChatView` / `EmptyThreadState`:** cover the highest-variance render states without snapshotting every event permutation. Non-obvious:
- Fresh thread hero, initial setup progress, and pre-history setup failure with Retry, including the preserved-worktree reuse path where `needsSetup` is already false
- Permission banner in both variants: write-escalation CTA visible vs dismiss-only for denied non-write tools
- Session-reconfigure progress banner stacked ahead of permission/staged-context banners
- Queued message bubble showing the staged-context `📎` indicator
- Diff-viewer action delivery canceled by a fast tab/sidebar switch does not still send into the old conversation after the request has already been cleared

---

Composer state, setting-change wiring, streaming bubble details, and live progress continue in [Supplement: Composer State and Live Progress](supplement-composer-and-live-progress.md).
