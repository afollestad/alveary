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

                ConversationTabs(
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

private struct ConversationTabs: View {
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ActivitySignal
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if conversations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(conversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(statusColor(for: statusForConversation(conversation)))
                                        .frame(width: 8, height: 8)
                                        .opacity(showsStatusDot(for: statusForConversation(conversation)) ? 1 : 0)

                                    Text(label(for: conversation))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedConversation.persistentModelID == conversation.persistentModelID
                                                ? Color.accentColor.opacity(0.16)
                                                : Color.secondary.opacity(0.08)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(for: selectedConversation))
                        .font(.headline)

                    Text(selectedConversation.provider ?? "Conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                onCreate()
            } label: {
                Label("New Conversation", systemImage: "plus")
            }
            .secondaryActionButtonStyle()
            .keyboardShortcut("t", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private extension ConversationTabs {
    func label(for conversation: Conversation) -> String {
        if let title = conversation.title, !title.isEmpty {
            return title
        }

        if conversation.isMain {
            return "Main"
        }

        return conversation.provider?.capitalized ?? "Conversation"
    }

    func showsStatusDot(for status: ActivitySignal) -> Bool {
        switch status {
        case .neutral, .stopped:
            return false
        case .busy, .idle, .error:
            return true
        }
    }

    func statusColor(for status: ActivitySignal) -> Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .neutral, .stopped:
            return .clear
        }
    }
}
