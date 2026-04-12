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
    let loadSkillCompletions: () async -> [Skill]
    let diffViewModel: DiffViewerViewModel

    @Environment(\.modelContext) private var uiModelContext
    @State private var createConversationError: String?

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
        if let conversation = appState.selectedConversation(in: thread) {
            VStack(spacing: 0) {
                if let createConversationError {
                    InlineBanner(message: createConversationError, severity: .error, autoDismissAfter: nil) {
                        self.createConversationError = nil
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                ThreadDetailConversationTabs(
                    conversations: conversations,
                    selectedConversation: conversation,
                    statusForConversation: { agentsManager.status(for: $0.id) },
                    onSelect: { appState.selectConversation($0, in: thread) },
                    onCreate: { Task { await createConversation() } }
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

private extension ThreadDetailView {
    func createConversation() async {
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            createConversationError = "Couldn't create conversation: thread no longer exists"
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
            createConversationError = nil

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
            createConversationError = "Couldn't create conversation: \(error.localizedDescription)"
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
