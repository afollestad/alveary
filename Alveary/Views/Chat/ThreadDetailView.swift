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
                        onRemove: { pendingDeleteConversation = $0 },
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
                        let conversationID = conversation.persistentModelID
                        pendingDeleteConversation = nil
                        Task { await removeConversation(id: conversationID) }
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

    func removeConversation(id: PersistentIdentifier) async {
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            conversationActionError = "Couldn't remove conversation: thread no longer exists"
            return
        }
        guard let dbConversation = uiModelContext.model(for: id) as? Conversation else {
            conversationActionError = "Couldn't remove conversation: it no longer exists"
            return
        }
        guard dbThread.conversations.count > 1 else {
            conversationActionError = "Couldn't remove conversation: threads must keep at least one conversation"
            return
        }

        do {
            try await agentsManager.destroyRuntime(conversationId: dbConversation.id)
            // Dismiss any delivered banner and clear the unread count before the row disappears,
            // so the dock badge and Notification Center both stay consistent with the live DB.
            notificationManager.markConversationRead(conversationId: dbConversation.id)
            uiModelContext.delete(dbConversation)
            try uiModelContext.save()
            conversationActionError = nil

            if appState.pendingDiffAction?.conversationID == id {
                appState.pendingDiffAction = nil
            }

            appState.repairSelectedConversationIfNeeded(for: dbThread)

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
            conversationActionError = "Couldn't remove conversation: \(error.localizedDescription)"
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
