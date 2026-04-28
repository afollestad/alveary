import SwiftData
import SwiftUI

struct ThreadDetailView: View {
    let thread: AgentThread
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel

    @Environment(\.modelContext) var uiModelContext
    @State var conversationActionError: String?
    @State private var editingConversationID: PersistentIdentifier?
    @State private var pendingDeleteConversation: Conversation?
    @State private var statusVersion = 0
    @State var projectTrustPrompt: ProjectTrustPrompt?
    @State var isCheckingProjectTrust = false

    private var conversations: [Conversation] {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        return conversations.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            if $0.isMain != $1.isMain {
                return $0.isMain && !$1.isMain
            }
            return $0.id < $1.id
        }
    }

    var body: some View {
        let conversations = conversations
        let selectedConversation = appState.selectedConversation(in: thread, conversations: conversations)
        let selectedConversationID = selectedConversation?.persistentModelID
        let conversationIDs = Set(conversations.map(\.id))
        let projectTrustContext = selectedConversation.flatMap(projectTrustContext(for:))
        let cachedProjectTrustStatus = projectTrustContext.flatMap(cachedProjectTrustStatus(for:))
        let visibleProjectTrustPrompt: ProjectTrustPrompt? = if let projectTrustContext {
            visibleProjectTrustPrompt(for: projectTrustContext, cachedStatus: cachedProjectTrustStatus)
        } else {
            nil
        }
        let isAwaitingProjectTrustCheck = projectTrustContext != nil &&
            cachedProjectTrustStatus == nil &&
            visibleProjectTrustPrompt == nil
        let isProjectTrustBlocked = visibleProjectTrustPrompt != nil ||
            isAwaitingProjectTrustCheck ||
            (isCheckingProjectTrust && cachedProjectTrustStatus == nil)

        return Group {
            if let conversation = selectedConversation {
                VStack(spacing: 0) {
                    if let conversationActionError {
                        InlineBanner(
                            message: conversationActionError,
                            severity: .error,
                            autoDismissAfter: nil,
                            onDismiss: { self.conversationActionError = nil }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    ThreadDetailConversationTabs(
                        conversations: conversations,
                        selectedConversation: conversation,
                        statusVersion: statusVersion,
                        statusForConversation: { $0.displayStatus(runtime: agentsManager.status(for: $0.id)) },
                        onSelect: { appState.selectConversation($0, in: thread) },
                        onCommitRename: { renameConversation($0, to: $1) },
                        onRemove: { conversation in
                            guard conversations.count > 1 else { return }
                            pendingDeleteConversation = conversation
                        },
                        onCreate: { Task { await createConversation() } },
                        isCreateDisabled: isProjectTrustBlocked,
                        editingConversationID: $editingConversationID
                    )

                    ConversationView(
                        conversation: conversation,
                        agentsManager: agentsManager,
                        runtimeStore: runtimeStore,
                        modelContext: modelContext,
                        settingsService: settingsService,
                        providerRegistry: providerRegistry,
                        worktreeManager: worktreeManager,
                        providerSetup: providerSetup,
                        contextWindowCache: contextWindowCache,
                        fileListManager: fileListManager,
                        projectTrustPrompt: visibleProjectTrustPrompt,
                        isProjectTrustBlocked: isProjectTrustBlocked,
                        onTrustProject: { prompt in
                            Task { await trustProject(prompt) }
                        },
                        onDenyProjectTrust: { prompt in
                            denyProjectTrust(prompt)
                        },
                        loadSkillCompletions: loadSkillCompletions,
                        diffViewModel: diffViewModel,
                        appState: appState
                    )
                    .id(conversation.id)
                }
                .task(id: thread.persistentModelID) {
                    appState.repairSelectedConversationIfNeeded(for: thread, conversations: conversations)
                }
                .task(id: selectedConversationID) {
                    cancelPendingDiffActionIfNeeded(selectedConversationID: selectedConversationID)
                }
                .task(id: projectTrustTaskID(for: conversation)) {
                    await refreshProjectTrustPrompt(for: conversation)
                }
                .confirmationDialog(
                    "Remove conversation?",
                    isPresented: Binding(
                        get: { pendingDeleteConversation != nil },
                        set: { isPresented in
                            if !isPresented {
                                pendingDeleteConversation = nil
                            }
                        }
                    ),
                    presenting: pendingDeleteConversation
                ) { conversation in
                    Button("Remove", role: .destructive) {
                        // Snapshot both the `PersistentIdentifier` and the UUID-string
                        // `id` synchronously here. `removeConversation` hops through
                        // `await agentsManager.destroyRuntime(...)` and a stale re-fetch
                        // via `modelContext.model(for:)` can return a zombie
                        // `Conversation` that traps on any persisted-property read. The
                        // dialog-message closure above (`conversation.displayName()`)
                        // already read from this same model reference synchronously to
                        // render the dialog, so reading `.id` at click time is on the
                        // same known-live frame.
                        let conversationID = conversation.persistentModelID
                        let conversationIDString = conversation.id
                        pendingDeleteConversation = nil
                        Task {
                            await removeConversation(
                                id: conversationID,
                                conversationIDString: conversationIDString
                            )
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        pendingDeleteConversation = nil
                    }
                } message: { conversation in
                    Text("This permanently deletes \(conversation.displayName()) and its saved messages.")
                }

            } else {
                EmptyStateView(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    heading: "Create your first conversation",
                    subtext: "Start a main or side conversation in this thread to begin chatting with your agent.",
                    actions: [
                        .init(title: "New Conversation", style: .primary) {
                            Task { await createConversation() }
                        }
                    ]
                )
                .task(id: thread.persistentModelID) {
                    appState.repairSelectedConversationIfNeeded(for: thread, conversations: conversations)
                }
                .task(id: selectedConversationID) {
                    cancelPendingDiffActionIfNeeded(selectedConversationID: selectedConversationID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentStatusChanged)) { notification in
            guard let conversationId = notification.userInfo?["conversationId"] as? String,
                  conversationIDs.contains(conversationId) else {
                return
            }

            // Tabs read `agentsManager.status(for:)` synchronously, so they need an
            // explicit invalidation when a conversation in this thread starts or
            // finishes work; otherwise the header can stay visually stale until some
            // unrelated state change happens to re-render the parent view.
            statusVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .claudeConfigChanged)) { _ in
            guard let selectedConversation else {
                return
            }

            Task {
                await refreshProjectTrustPrompt(for: selectedConversation)
            }
        }
        // Publish the thread-scoped create action so `AlvearyApp.commands`
        // can render a ⌘T "New Conversation" menu item that is disabled
        // when no thread is mounted (the focused value resolves to nil
        // outside this view, so the menu button reads `action == nil`).
        .focusedSceneValue(\.newConversationAction, newConversationAction(isDisabled: isProjectTrustBlocked))
    }
}

private extension ThreadDetailView {
    func newConversationAction(isDisabled: Bool) -> NewConversationActionKey.Value? {
        guard !isDisabled else {
            return nil
        }

        return {
            Task { await createConversation() }
        }
    }

    func renameConversation(_ conversation: Conversation, to newName: String) {
        guard let dbConversation = uiModelContext.resolveConversation(id: conversation.persistentModelID) else {
            conversationActionError = "Couldn't rename conversation: it no longer exists"
            return
        }

        dbConversation.title = dbConversation.persistedTitle(from: newName)

        do {
            try uiModelContext.save()
            conversationActionError = nil
        } catch {
            conversationActionError = "Couldn't rename conversation: \(error.localizedDescription)"
        }
    }

    func createConversation() async {
        guard !isCurrentProjectTrustBlocked() else {
            return
        }

        guard let dbThread = uiModelContext.resolveThread(id: thread.persistentModelID) else {
            conversationActionError = "Couldn't create conversation: thread no longer exists"
            return
        }

        let existingConversations = conversations
        let conversation = Conversation(
            provider: existingConversations.first(where: { $0.isMain })?.provider ?? existingConversations.first?.provider,
            isMain: false,
            displayOrder: (existingConversations.map(\.displayOrder).max() ?? -1) + 1,
            thread: dbThread
        )

        uiModelContext.insert(conversation)

        do {
            try uiModelContext.save()
            conversationActionError = nil

            guard case .thread(let selectedThread) = appState.selectedSidebarItem,
                  selectedThread.persistentModelID == thread.persistentModelID else {
                return
            }

            appState.selectConversation(conversation, in: dbThread)

            if let path = dbThread.worktreePath ?? dbThread.project?.path {
                let baseRef = dbThread.project?.baseRef ?? "main"
                let remoteName = dbThread.project?.remoteName
                let conversationIds = Set(existingConversations.map(\.id)).union([conversation.id])
                await diffViewModel.switchToDirectory(
                    path,
                    baseRef: baseRef,
                    remoteName: remoteName,
                    conversationIds: conversationIds
                )
            }
        } catch {
            conversationActionError = "Couldn't create conversation: \(error.localizedDescription)"
        }
    }

    func isCurrentProjectTrustBlocked() -> Bool {
        let selectedConversation = appState.selectedConversation(in: thread, conversations: conversations)
        guard let projectTrustContext = selectedConversation.flatMap(projectTrustContext(for:)) else {
            return false
        }

        let cachedStatus = cachedProjectTrustStatus(for: projectTrustContext)
        return cachedStatus == nil ||
            visibleProjectTrustPrompt(for: projectTrustContext, cachedStatus: cachedStatus) != nil
    }

    func removeConversation(id: PersistentIdentifier, conversationIDString: String) async {
        guard let dbThread = uiModelContext.resolveThread(id: thread.persistentModelID) else {
            conversationActionError = "Couldn't remove conversation: thread no longer exists"
            return
        }
        guard conversations.count > 1 else {
            conversationActionError = "Couldn't remove conversation: threads must keep at least one conversation"
            return
        }

        // `conversationIDString` was snapshotted synchronously by the caller (the
        // confirmation-dialog button) — deliberately do not refetch a `Conversation`
        // reference here to re-read its `.id`. `modelContext.model(for:)` can return a
        // zombie `@Model` reference whose backing store has already been invalidated,
        // and the first persisted-property read on that zombie traps with
        // `_assertionFailure`. Re-resolution post-await is still safe because by then
        // the store has settled and the nil-return branch catches a real deletion.
        selectNeighborIfClosingSelected(id: id, in: dbThread)

        let threadPersistentID = thread.persistentModelID

        do {
            try await agentsManager.destroyRuntime(conversationId: conversationIDString)

            // Re-resolve model references after the await for the same reason — the
            // pre-await `dbThread` / `dbConversation` may have been invalidated.
            guard let liveThread = uiModelContext.resolveThread(id: threadPersistentID) else {
                conversationActionError = nil
                return
            }
            guard let liveConversation = uiModelContext.resolveConversation(id: id) else {
                conversationActionError = nil
                appState.repairSelectedConversationIfNeeded(for: liveThread, conversations: conversations)
                return
            }

            // Dismiss any delivered banner and clear the unread count before the row disappears,
            // so the dock badge and Notification Center both stay consistent with the live DB.
            notificationManager.markConversationRead(conversationId: conversationIDString)
            uiModelContext.delete(liveConversation)
            try uiModelContext.save()
            conversationActionError = nil

            if appState.pendingDiffAction?.conversationID == id {
                appState.pendingDiffAction = nil
            }

            appState.repairSelectedConversationIfNeeded(for: liveThread, conversations: conversations)

            if let path = liveThread.worktreePath ?? liveThread.project?.path {
                let baseRef = liveThread.project?.baseRef ?? "main"
                let remoteName = liveThread.project?.remoteName
                let conversationIds = Set(conversations.map(\.id))
                await diffViewModel.switchToDirectory(
                    path,
                    baseRef: baseRef,
                    remoteName: remoteName,
                    conversationIds: conversationIds
                )
            }
        } catch {
            conversationActionError = "Couldn't remove conversation: \(error.localizedDescription)"
        }
    }

    // Before deleting the selected tab, pick its visual neighbor (next, falling
    // back to previous). `repairSelectedConversationIfNeeded` otherwise falls
    // back to the main conversation via its main-preference sort, which jumps
    // selection to the first tab rather than the adjacent one.
    func selectNeighborIfClosingSelected(id: PersistentIdentifier, in dbThread: AgentThread) {
        let order = conversations
        guard appState.selectedConversation(in: dbThread, conversations: order)?.persistentModelID == id,
              let removedIndex = order.firstIndex(where: { $0.persistentModelID == id }) else {
            return
        }
        let neighbor: Conversation? = if removedIndex + 1 < order.count {
            order[removedIndex + 1]
        } else if removedIndex > 0 {
            order[removedIndex - 1]
        } else {
            nil
        }
        if let neighbor {
            appState.selectConversation(neighbor, in: dbThread)
        }
    }

    func cancelPendingDiffActionIfNeeded(selectedConversationID: PersistentIdentifier?) {
        guard let request = appState.pendingDiffAction else {
            return
        }

        guard request.conversationID == selectedConversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }
}
