import SwiftData
import SwiftUI

struct ComposerCapabilities: Sendable {
    let supportedEffortLevels: [String]
    let supportedPermissionModes: [PermissionModeOption]
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
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Bindable var appState: AppState

    @State private var viewModel: ConversationViewModel

    private var activeWorkingDirectory: String? {
        conversation.thread?.worktreePath ?? conversation.thread?.project?.path
    }

    private var activeProviderID: String {
        conversation.provider ?? settingsService.current.defaultProvider
    }

    private var composerCapabilities: ComposerCapabilities {
        let provider = providerRegistry.provider(for: activeProviderID)

        return ComposerCapabilities(
            supportedEffortLevels: provider?.supportedEffortLevels ?? [],
            supportedPermissionModes: provider?.supportedPermissionModes ?? [],
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
        contextWindowCache: any ContextWindowCache,
        fileListManager: FileListManager,
        projectTrustPrompt: ProjectTrustPrompt? = nil,
        isProjectTrustBlocked: Bool = false,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void = { _ in },
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void = { _ in },
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
        self.contextWindowCache = contextWindowCache
        self.fileListManager = fileListManager
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
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
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache
        ))
    }

    var body: some View {
        let transcriptTypography = TranscriptTypography(settings: settingsService.current)

        ChatView(
            viewModel: viewModel,
            conversation: conversation,
            composerCapabilities: composerCapabilities,
            providerID: activeProviderID,
            contextWindowCache: contextWindowCache,
            workingDirectory: activeWorkingDirectory,
            projectTrustPrompt: projectTrustPrompt,
            isProjectTrustBlocked: isProjectTrustBlocked,
            onTrustProject: onTrustProject,
            onDenyProjectTrust: onDenyProjectTrust,
            loadFileCompletions: Self.makeFileCompletionLoader(
                fileListManager: fileListManager,
                workingDirectory: activeWorkingDirectory
            ),
            loadSkillCompletions: loadSkillCompletions,
            transcriptTypography: transcriptTypography,
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

            let threadID = thread.persistentModelID
            let baseRef = thread.project?.baseRef ?? "main"
            let remoteName = thread.project?.remoteName
            let conversationIds = liveConversationIDs(for: threadID)

            Task {
                await fileListManager.warmCache(for: newPath)
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
                      selectedConversation(
                          in: selectedThread,
                          modelContext: modelContext,
                          appState: appState
                      )?.persistentModelID == conversation.persistentModelID else {
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

    func liveConversationIDs(for threadID: PersistentIdentifier) -> Set<String> {
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return Set(((try? modelContext.fetch(descriptor)) ?? []).map(\.id))
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
