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
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel

    @Environment(\.modelContext) private var uiModelContext
    @State private var conversationActionError: String?
    @State private var editingConversationID: PersistentIdentifier?
    @State private var pendingDeleteConversation: Conversation?

    private var conversations: [Conversation] {
        thread.conversations.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            if $0.isMain != $1.isMain {
                return $0.isMain && !$1.isMain
            }
            return $0.id < $1.id
        }
    }

    private var selectedConversationID: PersistentIdentifier? {
        appState.selectedConversation(in: thread)?.persistentModelID
    }

    var body: some View {
        Group {
            if let conversation = appState.selectedConversation(in: thread) {
                VStack(spacing: 0) {
                    if let conversationActionError {
                        InlineBanner(message: conversationActionError, severity: .error, autoDismissAfter: nil) {
                            self.conversationActionError = nil
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    ThreadDetailConversationTabs(
                        conversations: conversations,
                        selectedConversation: conversation,
                        statusForConversation: { $0.displayStatus(runtime: agentsManager.status(for: $0.id)) },
                        onSelect: { appState.selectConversation($0, in: thread) },
                        onCommitRename: { renameConversation($0, to: $1) },
                        onRemove: { conversation in
                            guard conversations.count > 1 else { return }
                            pendingDeleteConversation = conversation
                        },
                        onCreate: { Task { await createConversation() } },
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
                        fileListManager: fileListManager,
                        loadSkillCompletions: loadSkillCompletions,
                        diffViewModel: diffViewModel,
                        appState: appState
                    )
                    .id(conversation.id)
                }
                .task(id: thread.persistentModelID) {
                    appState.repairSelectedConversationIfNeeded(for: thread)
                }
                .task(id: selectedConversationID) {
                    cancelPendingDiffActionIfNeeded()
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
                    appState.repairSelectedConversationIfNeeded(for: thread)
                }
                .task(id: selectedConversationID) {
                    cancelPendingDiffActionIfNeeded()
                }
            }
        }
        // Publish the thread-scoped create action so `AlvearyApp.commands`
        // can render a ⌘T "New Conversation" menu item that is disabled
        // when no thread is mounted (the focused value resolves to nil
        // outside this view, so the menu button reads `action == nil`).
        .focusedSceneValue(\.newConversationAction) {
            Task { await createConversation() }
        }
    }
}

private extension ThreadDetailView {
    func renameConversation(_ conversation: Conversation, to newName: String) {
        guard let dbConversation = uiModelContext.model(for: conversation.persistentModelID) as? Conversation else {
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
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            conversationActionError = "Couldn't create conversation: thread no longer exists"
            return
        }

        let conversation = Conversation(
            provider: dbThread.conversations.first(where: { $0.isMain })?.provider ?? dbThread.conversations.first?.provider,
            isMain: false,
            displayOrder: (dbThread.conversations.map(\.displayOrder).max() ?? -1) + 1,
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
                let conversationIds = Set(dbThread.conversations.map(\.id))
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

    func removeConversation(id: PersistentIdentifier, conversationIDString: String) async {
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            conversationActionError = "Couldn't remove conversation: thread no longer exists"
            return
        }
        guard dbThread.conversations.count > 1 else {
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
            guard let liveThread = uiModelContext.model(for: threadPersistentID) as? AgentThread else {
                conversationActionError = nil
                return
            }
            guard let liveConversation = uiModelContext.model(for: id) as? Conversation else {
                conversationActionError = nil
                appState.repairSelectedConversationIfNeeded(for: liveThread)
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

            appState.repairSelectedConversationIfNeeded(for: liveThread)

            if let path = liveThread.worktreePath ?? liveThread.project?.path {
                let baseRef = liveThread.project?.baseRef ?? "main"
                let remoteName = liveThread.project?.remoteName
                let conversationIds = Set(liveThread.conversations.map(\.id))
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
        guard appState.selectedConversation(in: dbThread)?.persistentModelID == id,
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

    func cancelPendingDiffActionIfNeeded() {
        guard let request = appState.pendingDiffAction else {
            return
        }

        guard request.conversationID == selectedConversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }
}
