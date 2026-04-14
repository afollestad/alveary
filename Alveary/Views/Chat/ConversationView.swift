import SwiftData
import SwiftUI

struct ComposerCapabilities: Sendable {
    let supportedEffortLevels: [String]
    let supportedPermissionModes: [PermissionModeOption]
    let suggestedWriteEscalationMode: String?
    let writeEscalationEligibleTools: Set<String>
    let supportsMidTurnSteering: Bool
}

struct ConversationView: View {
    let conversation: Conversation
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let modelContext: ModelContext
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let fileListManager: FileListManager
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Bindable var appState: AppState

    @State private var viewModel: ConversationViewModel

    private var activeWorkingDirectory: String? {
        conversation.thread?.worktreePath ?? conversation.thread?.project?.path
    }

    private var composerCapabilities: ComposerCapabilities {
        let providerID = conversation.provider ?? settingsService.current.defaultProvider
        let provider = providerRegistry.provider(for: providerID)

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
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
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
        _viewModel = State(initialValue: ConversationViewModel(
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
            agentsManager: agentsManager,
            modelContext: modelContext,
            diffViewModel: diffViewModel,
            composerCapabilities: composerCapabilities,
            workingDirectory: activeWorkingDirectory,
            loadFileCompletions: Self.makeFileCompletionLoader(
                fileListManager: fileListManager,
                workingDirectory: activeWorkingDirectory
            ),
            loadSkillCompletions: loadSkillCompletions,
            appState: appState
        )
        .task {
            viewModel.activateViewLifecycle()
            if let path = activeWorkingDirectory {
                await fileListManager.warmCache(for: path)
            }
        }
        .onDisappear {
            viewModel.deactivateViewLifecycle()
        }
        .onChange(of: activeWorkingDirectory) { _, newPath in
            guard let newPath,
                  case .thread(let selectedThread) = appState.selectedSidebarItem,
                  selectedThread.persistentModelID == conversation.thread?.persistentModelID,
                  let thread = conversation.thread else {
                return
            }

            Task {
                await fileListManager.warmCache(for: newPath)
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

private extension ConversationView {
    static func makeFileCompletionLoader(
        fileListManager: FileListManager,
        workingDirectory: String?
    ) -> @Sendable () async -> [String] {
        {
            guard let workingDirectory else {
                return []
            }
            return await fileListManager.files(for: workingDirectory)
        }
    }
}
